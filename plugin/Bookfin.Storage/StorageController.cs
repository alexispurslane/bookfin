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

    private static bool ValidIdentity(string identity)
        => identity.Length is >= 1 and <= 128
            && identity.All(character => char.IsAsciiLetterOrDigit(character) || character is '.' or '_' or ':' or '-');

    [HttpGet]
    public IActionResult Discover([FromQuery] long after = 0, [FromQuery] int limit = 4)
    {
        if (Owner == Guid.Empty) return Forbid();
        if (after < 0 || limit is < 1 or > 4) return BadRequest();
        return Ok(store.Discover(Owner, after, limit));
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
        if (!ValidIdentity(identity) || string.IsNullOrEmpty(upload.Payload)) return BadRequest();
        if (Encoding.UTF8.GetByteCount(upload.Payload) > 65536) return StatusCode(413);
        var result = store.Put(Owner, identity, upload.Payload);
        return result.Status is 200 or 201 ? StatusCode(result.Status, result.Object) : StatusCode(result.Status);
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
