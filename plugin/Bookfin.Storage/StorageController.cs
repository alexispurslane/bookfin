using System.Text;
using Jellyfin.Api.Extensions;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace Bookfin.Storage;

[ApiController]
[Authorize]
[Route("BookfinStorage/v1/objects")]
public sealed class StorageController : ControllerBase
{
    private readonly ObjectStore store;

    public StorageController(ObjectStore store) => this.store = store;

    private Guid Owner => User.GetUserId();

    private static bool ValidIdentity(string? identity)
        => identity is { Length: >= 1 and <= 128 }
            && identity.All(character => char.IsAsciiLetterOrDigit(character) || character is '.' or '_' or ':' or '-');

    [HttpGet]
    public IActionResult Discover([FromQuery] long after = 0, [FromQuery] int limit = 4)
    {
        if (Owner == Guid.Empty) return Forbid();
        if (after < 0 || limit is < 1 or > 4) return BadRequest();
        return Page(after, limit);
    }

    [HttpGet("/BookfinStorage/v2/objects")]
    public IActionResult DiscoverBatch([FromQuery] long after = 0,
        [FromQuery] int limit = ObjectStore.MaximumObjects)
    {
        if (Owner == Guid.Empty) return Forbid();
        if (after < 0 || limit is < 1 or > ObjectStore.MaximumObjects) return BadRequest();
        return Page(after, limit);
    }

    private IActionResult Page(long after, int limit)
    {
        var page = store.Discover(Owner, after, limit);
        return Ok(new { page.Objects, page.Cursor, page.HasMore,
            PluginVersion = typeof(Plugin).Assembly.GetName().Version!.ToString() });
    }

    [HttpGet("{identity}")]
    public IActionResult Read(string identity)
    {
        if (Owner == Guid.Empty) return Forbid();
        if (!ValidIdentity(identity)) return BadRequest();
        var stored = store.Read(Owner, identity);
        if (stored is null) return NotFound();
        return stored.Deleted ? StatusCode(410) : Ok(stored);
    }

    [HttpPut("{identity}")]
    [RequestSizeLimit(524288)]
    public IActionResult Put(string identity, [FromBody] Upload upload)
    {
        if (Owner == Guid.Empty) return Forbid();
        var validation = Validate(new(identity, upload.Payload));
        if (validation != 200) return StatusCode(validation);
        var result = store.Put(Owner, identity, upload.Payload);
        return result.Status is 200 or 201 ? StatusCode(result.Status, result.Object) : StatusCode(result.Status);
    }

    [HttpPut("/BookfinStorage/v2/objects")]
    [RequestSizeLimit(8388608)]
    public IActionResult PutBatch([FromBody] UploadBatch batch)
    {
        if (Owner == Guid.Empty) return Forbid();
        if (batch.Objects is null || batch.Objects.Count is < 1 or > ObjectStore.MaximumObjects) return BadRequest();
        var identities = new HashSet<string>(StringComparer.Ordinal);
        var bytes = 0;
        foreach (var upload in batch.Objects)
        {
            var validation = Validate(upload);
            if (validation != 200) return StatusCode(validation);
            if (!identities.Add(upload.Id)) return BadRequest();
            bytes += Encoding.UTF8.GetByteCount(upload.Payload);
            if (bytes > ObjectStore.MaximumGroupBytes) return StatusCode(413);
        }
        return Ok(new { Results = store.PutMany(Owner, batch.Objects) });
    }

    private static int Validate(ObjectUpload? upload)
    {
        if (upload is null || !ValidIdentity(upload.Id) || string.IsNullOrEmpty(upload.Payload)) return 400;
        return Encoding.UTF8.GetByteCount(upload.Payload) > ObjectStore.MaximumPayloadBytes ? 413 : 200;
    }

    [HttpDelete("{identity}")]
    public IActionResult Delete(string identity)
    {
        if (Owner == Guid.Empty) return Forbid();
        if (!ValidIdentity(identity)) return BadRequest();
        store.Delete(Owner, identity);
        return NoContent();
    }
}

public sealed record Upload(string Payload);
public sealed record UploadBatch(IReadOnlyList<ObjectUpload> Objects);
