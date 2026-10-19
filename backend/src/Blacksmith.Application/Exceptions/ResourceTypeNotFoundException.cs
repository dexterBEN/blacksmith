namespace Blacksmith.Application.Exceptions;

public sealed class ResourceTypeNotFoundException(Guid resourceTypeId, Exception? innerException = null)
    : Exception("Resource type not found.", innerException)
{
    public Guid ResourceTypeId { get; } = resourceTypeId;
}
