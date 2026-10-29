namespace Blacksmith.Application.Exceptions;

public sealed class DesignDeletionConflictException(Guid designId, Exception? innerException = null)
    : Exception("Cannot delete this design: deployment history exists or its resources changed concurrently.", innerException)
{
    public Guid DesignId { get; } = designId;
}
