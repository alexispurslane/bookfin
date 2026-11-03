using MediaBrowser.Common.Plugins;

namespace Bookfin.Storage;

public sealed class Plugin : BasePlugin
{
    public Plugin()
    {
        var assembly = GetType().Assembly;
        SetAttributes(assembly.Location, Path.GetDirectoryName(assembly.Location)!, assembly.GetName().Version!);
    }

    public override string Name => "Bookfin Storage";
    public override string Description => "Private per-user immutable storage for Bookfin personal records";
    public override Guid Id => new("55fb5a92-7fbd-411c-9838-6ee4c88d168b");
}
