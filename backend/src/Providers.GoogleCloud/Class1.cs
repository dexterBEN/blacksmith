using CloudServices.Core;
using Google.Cloud.Storage.V1;
using Google.Apis.Auth.OAuth2;

namespace Providers.GoogleCloud;

public class GoogleCloudStorageService : ICloudStorageService
{
    private readonly StorageClient _storageClient;

    public GoogleCloudStorageService()
    {
        GoogleCredential credential = GoogleCredential.GetApplicationDefault();
        _storageClient = StorageClient.Create(credential);
    }

    public async Task<string> CreateBucketAsync(string projectId, string bucketName)
    {
        var bucket = await _storageClient.CreateBucketAsync(
            projectId,
            new Google.Apis.Storage.v1.Data.Bucket
            {
                Name = bucketName
            }
        );
        return bucket.Name;
    }
}
