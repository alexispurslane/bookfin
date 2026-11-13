using System.Diagnostics;
using System.Text;
using System.Text.Json.Serialization;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Controller;
using MediaBrowser.Controller.Plugins;
using Microsoft.Data.Sqlite;
using Microsoft.Extensions.DependencyInjection;

namespace Bookfin.Storage;

public sealed record StoredObject(string Id, long Sequence,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? Payload)
{
    public bool Deleted => Payload is null;
}

public sealed record ObjectPage(IReadOnlyList<StoredObject> Objects, long Cursor, bool HasMore);

public sealed record ObjectUpload(string Id, string Payload);
public sealed record UploadResult(string Id, int Status,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] StoredObject? Object);

public sealed class StorageServices : IPluginServiceRegistrator
{
    public void RegisterServices(IServiceCollection services, IServerApplicationHost applicationHost)
        => services.AddSingleton<ObjectStore>();
}

public sealed class ObjectStore
{
    // Invariants: identities and positive sequences are unique per owner;
    // immutable payloads never change; null payloads remain deletion barriers.
    // Every group commits together. CheckInvariants checks these on demand.
    public const int MaximumObjects = 256;
    public const int MaximumPayloadBytes = 65536;
    public const int MaximumGroupBytes = 1048576;
    private readonly string connectionString;

    public ObjectStore(IApplicationPaths paths)
    {
        connectionString = new SqliteConnectionStringBuilder
        {
            DataSource = Path.Combine(paths.DataPath, "bookfin-storage-v1.sqlite"),
            Pooling = false,
            DefaultTimeout = 10,
        }.ToString();
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS objects (
                owner TEXT NOT NULL,
                identity TEXT NOT NULL,
                sequence INTEGER NOT NULL CHECK(sequence > 0),
                payload TEXT CHECK(payload IS NULL OR length(CAST(payload AS BLOB)) > 0),
                PRIMARY KEY(owner, identity),
                UNIQUE(owner, sequence)
            );
            """;
        command.ExecuteNonQuery();
        if (Environment.GetEnvironmentVariable("BOOKFIN_STORAGE_CHECK_INVARIANTS") == "1")
        {
            CheckInvariants();
        }
    }

    private SqliteConnection Open()
    {
        var connection = new SqliteConnection(connectionString);
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText = "PRAGMA synchronous=FULL;";
        command.ExecuteNonQuery();
        return connection;
    }

    public StoredObject? Read(Guid owner, string identity)
    {
        using var connection = Open();
        return Read(connection, null, owner, identity);
    }

    private static StoredObject? Read(SqliteConnection connection, SqliteTransaction? transaction, Guid owner, string identity)
    {
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = "SELECT identity, sequence, payload FROM objects WHERE owner=$owner AND identity=$identity";
        command.Parameters.AddWithValue("$owner", owner.ToString("N"));
        command.Parameters.AddWithValue("$identity", identity);
        using var reader = command.ExecuteReader();
        return reader.Read() ? Decode(reader) : null;
    }

    private static StoredObject Decode(SqliteDataReader reader)
        => new(reader.GetString(0), reader.GetInt64(1), reader.IsDBNull(2) ? null : reader.GetString(2));

    public ObjectPage Discover(Guid owner, long after, int limit)
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = """
            SELECT identity, sequence, payload FROM objects
            WHERE owner=$owner AND sequence>$after ORDER BY sequence LIMIT $count
            """;
        command.Parameters.AddWithValue("$owner", owner.ToString("N"));
        command.Parameters.AddWithValue("$after", after);
        command.Parameters.AddWithValue("$count", limit + 1);
        using var reader = command.ExecuteReader();
        var objects = new List<StoredObject>();
        var bytes = 0;
        var hasMore = false;
        while (reader.Read())
        {
            var item = Decode(reader);
            var size = item.Payload is null ? 0 : Encoding.UTF8.GetByteCount(item.Payload);
            if (objects.Count == limit || bytes + size > MaximumGroupBytes)
            {
                hasMore = true;
                break;
            }
            objects.Add(item);
            bytes += size;
        }
        return new(objects, objects.Count == 0 ? after : objects[^1].Sequence, hasMore);
    }

    /// Single uploads and batches share the same transaction and immutable-object rules.
    public UploadResult Put(Guid owner, string identity, string payload)
        => PutMany(owner, [new(identity, payload)])[0];

    /// Commits every successful item together. Conflicting or retired identities
    /// are returned individually without changing them. A storage failure commits
    /// none of the group. HTTP size/identity guards run before this operation.
    public IReadOnlyList<UploadResult> PutMany(Guid owner, IReadOnlyList<ObjectUpload> uploads)
    {
        using var connection = Open();
        using var transaction = connection.BeginTransaction(deferred: false);
        var results = new List<UploadResult>(uploads.Count);
        foreach (var upload in uploads)
        {
            results.Add(Put(connection, transaction, owner, upload.Id, upload.Payload));
        }
        transaction.Commit();
        return results;
    }

    private static UploadResult Put(SqliteConnection connection, SqliteTransaction transaction,
        Guid owner, string identity, string payload)
    {
        Debug.Assert(transaction.Connection == connection);
        var existing = Read(connection, transaction, owner, identity);
        if (existing is not null)
        {
            var status = existing.Deleted ? 410 : existing.Payload == payload ? 200 : 409;
            return new(identity, status, status == 200 ? existing : null);
        }
        var stored = Replace(connection, transaction, owner, identity, payload);
        return new(identity, 201, stored);
    }

    public void Delete(Guid owner, string identity)
    {
        using var connection = Open();
        using var transaction = connection.BeginTransaction(deferred: false);
        if (Read(connection, transaction, owner, identity)?.Deleted == true)
        {
            return;
        }
        Replace(connection, transaction, owner, identity, null);
        transaction.Commit();
    }

    private static StoredObject Replace(SqliteConnection connection, SqliteTransaction transaction,
        Guid owner, string identity, string? payload)
    {
        Debug.Assert(transaction.Connection == connection);
        using var command = connection.CreateCommand();
        command.Transaction = transaction;
        command.CommandText = """
            INSERT OR REPLACE INTO objects(owner, identity, sequence, payload)
            VALUES ($owner, $identity,
                (SELECT COALESCE(MAX(sequence), 0) + 1 FROM objects WHERE owner=$owner), $payload)
            RETURNING identity, sequence, payload
            """;
        command.Parameters.AddWithValue("$owner", owner.ToString("N"));
        command.Parameters.AddWithValue("$identity", identity);
        command.Parameters.AddWithValue("$payload", (object?)payload ?? DBNull.Value);
        using var reader = command.ExecuteReader();
        if (!reader.Read())
        {
            throw new InvalidOperationException("A committed object must have a sequence");
        }
        var stored = Decode(reader);
        Debug.Assert(stored.Sequence > 0 && stored.Id == identity && stored.Payload == payload);
        return stored;
    }

    public void CheckInvariants()
    {
        using var connection = Open();
        using var command = connection.CreateCommand();
        command.CommandText = "PRAGMA integrity_check;";
        if (!string.Equals(command.ExecuteScalar() as string, "ok", StringComparison.Ordinal))
        {
            throw new InvalidOperationException("Bookfin storage integrity failed");
        }
        command.CommandText = """
            SELECT COUNT(*) FROM objects
            WHERE length(owner) != 32 OR length(identity) NOT BETWEEN 1 AND 128
                OR sequence <= 0 OR (payload IS NOT NULL AND length(CAST(payload AS BLOB)) = 0)
            """;
        if (Convert.ToInt64(command.ExecuteScalar()) != 0)
        {
            throw new InvalidOperationException("Bookfin storage invariants failed");
        }
    }
}
