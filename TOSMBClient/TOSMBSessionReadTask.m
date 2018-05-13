//
//  TOSMBSessionReadTask.m
//  libchardet
//
//  Created by Albert Park on 4/21/18.
//

#import "TOSMBSessionReadTask.h"

#import "TOSMBSessionReadTaskPrivate.h"
#import "TOSMBSessionPrivate.h"

@interface TOSMBSessionReadTask()

@property (nonatomic, strong, readwrite) NSString *sourceFilePath;
//@property (nonatomic, strong, readwrite) NSString *destinationFilePath;
//@property (nonatomic, strong) NSString *tempFilePath;
@property (nonatomic, strong, readwrite) NSMutableData *data;

@property (nonatomic, strong) TOSMBSessionFile *file;
@property (nonatomic, strong) NSDate *modificationTime;

@property (assign, readwrite) int64_t countOfBytesReceived;
@property (assign, readwrite) int64_t countOfBytesExpectedToReceive;

/** Feedback handlers */
@property (nonatomic, weak) id<TOSMBSessionReadTaskDelegate> delegate;
@property (nonatomic, copy) void (^successHandler)(NSData *data);


/* Feedback events sent to either the delegate or callback blocks */
- (void)didSucceedWithData:(NSData *)data;
- (void)didUpdateWriteBytes:(uint64_t)bytesWritten totalBytesWritten:(uint64_t)totalBytesWritten totalBytesExpected:(uint64_t)totalBytesExpected;
- (void)didResumeAtOffset:(uint64_t)bytesWritten totalBytesExpected:(uint64_t)totalBytesExpected;

@end

@implementation TOSMBSessionReadTask

@dynamic delegate;
@dynamic failHandler;
@dynamic state;

- (instancetype)init
{
  //This class cannot be instantiated on its own.
  [self doesNotRecognizeSelector:_cmd];
  return nil;
}



- (instancetype)initWithSession:(TOSMBSession *)session filePath:(NSString *)filePath delegate:(id<TOSMBSessionReadTaskDelegate>)delegate
{
  if ((self = [super initWithSession:session])) {
    _sourceFilePath = filePath;
    _data = [[NSMutableData alloc] init];
    self.delegate = delegate;
    
    self.modificationTime = nil;
  }
  
  return self;
}

- (instancetype)initWithSession:(TOSMBSession *)session filePath:(NSString *)filePath progressHandler:(id)progressHandler successHandler:(id)successHandler failHandler:(id)failHandler
{
  if ((self = [super initWithSession:session])) {
    self.session = session;
    _sourceFilePath = filePath;
    _data = [[NSMutableData alloc] init];
    
    self.progressHandler = progressHandler;
    _successHandler = successHandler;
    self.failHandler = failHandler;
    
    self.modificationTime = nil;
  }
  
  return self;
}

#pragma mark - Public Control Methods -


- (void)cancel
{
  if (self.state != TOSMBSessionTaskStateRunning)
  return;
  _data.length = 0;
  self.modificationTime = nil;
  
  [self.taskOperation cancel];
  self.state = TOSMBSessionTaskStateCancelled;
  
  self.taskOperation = nil;
}

#pragma mark - Feedback Methods -
- (BOOL)canBeResumed
{
  if (self.modificationTime && [self.modificationTime isEqual:self.file.modificationTime] == NO) {
    return NO;
  }
  
  return YES;
}


- (void)didSucceedWithData:(NSData *)data
{
  dispatch_sync(dispatch_get_main_queue(), ^{
    if (self.delegate && [self.delegate respondsToSelector:@selector(readTask:didFinishDownloadingForData:)])
    [self.delegate readTask:self didFinishDownloadingForData:data];
    
    if (self.successHandler)
    self.successHandler(data);
  });
}

- (void)didFailWithError:(NSError *)error
{
  [super didFailWithError:error];
  dispatch_sync(dispatch_get_main_queue(), ^{
    if (self.delegate && [self.delegate respondsToSelector:@selector(readTask:didCompleteWithError:)])
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [self.delegate readTask:self didCompleteWithError:error];
#pragma clang diagnostic pop
    if (self.failHandler)
    self.failHandler(error);
  });
}

- (void)didUpdateWriteBytes:(uint64_t)bytesWritten totalBytesWritten:(uint64_t)totalBytesWritten totalBytesExpected:(uint64_t)totalBytesExpected
{
  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
    if (self.delegate && [self.delegate respondsToSelector:@selector(readTask:didWriteBytes:totalBytesReceived:totalBytesExpectedToReceive:)])
    [self.delegate readTask:self didWriteBytes:bytesWritten totalBytesReceived:self.countOfBytesReceived totalBytesExpectedToReceive:self.countOfBytesExpectedToReceive];
    
    if (self.progressHandler)
    self.progressHandler(self.countOfBytesReceived, self.countOfBytesExpectedToReceive);
  }];
}

- (void)didResumeAtOffset:(uint64_t)bytesWritten totalBytesExpected:(uint64_t)totalBytesExpected
{
  [[NSOperationQueue mainQueue] addOperationWithBlock:^{
    if (self.delegate && [self.delegate respondsToSelector:@selector(readTask:didResumeAtOffset:totalBytesExpectedToReceive:)])
    [self.delegate readTask:self didResumeAtOffset:bytesWritten totalBytesExpectedToReceive:totalBytesExpected];
  }];
}

#pragma mark - Downloading -

- (void)performTaskWithOperation:(__weak NSBlockOperation *)weakOperation
{
  if (weakOperation.isCancelled)
  return;
  
  smb_tid treeID = 0;
  smb_fd fileID = 0;
  
  //---------------------------------------------------------------------------------------
  //Connect to SMB device
  
  self.smbSession = smb_session_new();
  
  //First, check to make sure the server is there, and to acquire its attributes
  __block NSError *error = nil;
  dispatch_sync(self.session.serialQueue, ^{
    error = [self.session attemptConnectionWithSessionPointer:self.smbSession];
  });
  if (error) {
    [self didFailWithError:error];
    self.cleanupBlock(treeID, fileID);
    return;
  }
  
  if (weakOperation.isCancelled) {
    self.cleanupBlock(treeID, fileID);
    return;
  }
  
  //---------------------------------------------------------------------------------------
  //Connect to share
  
  //Next attach to the share we'll be using
  NSString *shareName = [self.session shareNameFromPath:self.sourceFilePath];
  const char *shareCString = [shareName cStringUsingEncoding:NSUTF8StringEncoding];
  
  if (smb_tree_connect(self.smbSession, shareCString, &treeID) != 0) {
    [self didFailWithError:errorForErrorCode(TOSMBSessionErrorCodeShareConnectionFailed)];
    self.cleanupBlock(treeID, fileID);
    return;
  }
  
  if (weakOperation.isCancelled) {
    self.cleanupBlock(treeID, fileID);
    return;
  }
  
  //---------------------------------------------------------------------------------------
  //Find the target file
  
  NSString *formattedPath = [self.session filePathExcludingSharePathFromPath:self.sourceFilePath];
  formattedPath = [NSString stringWithFormat:@"\\%@",formattedPath];
  formattedPath = [formattedPath stringByReplacingOccurrencesOfString:@"/" withString:@"\\\\"];
  
  //Get the file info we'll be working off
  self.file = [self requestFileForItemAtPath:formattedPath inTree:treeID];
  if (self.file == nil) {
    [self didFailWithError:errorForErrorCode(TOSMBSessionErrorCodeFileNotFound)];
    self.cleanupBlock(treeID, fileID);
    return;
  }
  
  if (weakOperation.isCancelled) {
    self.cleanupBlock(treeID, fileID);
    return;
  }
  
  if (self.file.directory) {
    [self didFailWithError:errorForErrorCode(TOSMBSessionErrorCodeDirectoryDownloaded)];
    self.cleanupBlock(treeID, fileID);
    return;
  }
  
  self.countOfBytesExpectedToReceive = self.file.fileSize;
  
  //---------------------------------------------------------------------------------------
  //Open the file handle
  
  smb_fopen(self.smbSession, treeID, [formattedPath cStringUsingEncoding:NSUTF8StringEncoding], SMB_MOD_RO, &fileID);
  if (!fileID) {
    [self didFailWithError:errorForErrorCode(TOSMBSessionErrorCodeFileNotFound)];
    self.cleanupBlock(treeID, fileID);
    return;
  }
  
  if (weakOperation.isCancelled) {
    self.cleanupBlock(treeID, fileID);
    return;
  }
  
  
  //---------------------------------------------------------------------------------------
  //Start downloading
  
  //Create a new blank file to write to
  if (self.canBeResumed == NO){
    _data.length = 0;
    self.modificationTime = nil;
  }
  
  //Open a handle to the file and skip ahead if we're resuming
  unsigned long long seekOffset = _data.length;
  self.countOfBytesReceived = seekOffset;
  
  //Create a background handle so the download will continue even if the app is suspended
  self.backgroundTaskIdentifier = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{ [self suspend]; }];
  
  if (seekOffset > 0) {
    smb_fseek(self.smbSession, fileID, (ssize_t)seekOffset, SMB_SEEK_SET);
    [self didResumeAtOffset:seekOffset totalBytesExpected:self.countOfBytesExpectedToReceive];
  }
  
  //Perform the file download
  int64_t bytesRead = 0;
  NSInteger bufferSize = 65535;
  char *buffer = malloc(bufferSize);
  
  do {
    //Read the bytes from the network device
    bytesRead = smb_fread(self.smbSession, fileID, buffer, bufferSize);
    if (bytesRead < 0) {
      [self fail];
      [self didFailWithError:errorForErrorCode(TOSMBSessionErrorCodeFileDownloadFailed)];
      break;
    }
    
    //Save them to the NSData
    [_data appendBytes:buffer length:bytesRead];
    
    if (weakOperation.isCancelled)
    break;
    
    self.countOfBytesReceived += bytesRead;
    
    [self didUpdateWriteBytes:bytesRead totalBytesWritten:self.countOfBytesReceived totalBytesExpected:self.countOfBytesExpectedToReceive];
  } while (bytesRead > 0);
  
  //Set the modification date to match the one on the SMB device so we can compare the two at a later date
  self.modificationTime = self.file.modificationTime;

  free(buffer);
//  [fileHandle closeFile];
  
  if (weakOperation.isCancelled  || self.state != TOSMBSessionTaskStateRunning) {
    self.cleanupBlock(treeID, fileID);
    return;
  }
  
  //---------------------------------------------------------------------------------------
  //Move the finished file to its destination
  
  //Workout the destination of the file and move it
  
  self.state = TOSMBSessionTaskStateCompleted;
  
  //Alert the delegate that we finished, so they may perform any additional cleanup operations
  [self didSucceedWithData:_data];
  
  //Perform a final cleanup of all handles and references
  self.cleanupBlock(treeID, fileID);
}

@end
