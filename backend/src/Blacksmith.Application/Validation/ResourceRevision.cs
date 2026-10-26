using Blacksmith.Application.Exceptions;

namespace Blacksmith.Application.Validation;

public static class ResourceRevision
{
    public static long Next(long revision) => revision is > 0 and < long.MaxValue
        ? revision + 1
        : throw new ResourceConflictException("revision_exhausted", "The Resource revision cannot be advanced.");
}
