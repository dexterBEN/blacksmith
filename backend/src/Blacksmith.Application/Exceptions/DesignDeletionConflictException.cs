namespace Blacksmith.Application.Exceptions;

public sealed class DesignDeletionConflictException(Guid designId, Exception? innerException = null)
    : Exception("Cannot delete a design that contains resources.", innerException)
{
    public Guid DesignId { get; } = designId;
}
