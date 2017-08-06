//
//  TOSMBSessionDeleteTask.m
//  TOSMBClient
//
//  Created by Albert Park on 8/5/17.
//


#import <CommonCrypto/CommonDigest.h>

#import "TOSMBSessionDeleteTask.h"
#import "TOSMBSessionDeleteTaskPrivate.h"
#import "TOSMBSessionPrivate.h"

@interface TOSMBSessionDeleteTask()

@property (nonatomic, strong, readwrite) NSString *sourceFilePath;

@property (nonatomic, strong) TOSMBSessionFile *file;


/** Feedback handlers */
@property (nonatomic, weak) id<TOSMBSessionDeleteTaskDelegate> delegate;
@property (nonatomic, copy) void (^successHandler)(void);

@end

@implementation TOSMBSessionDeleteTask

@dynamic delegate;
@dynamic failHandler;
@dynamic state;

- (instancetype)initWithSession:(TOSMBSession *)session
                           path:(NSString *)path
                           data:(NSData *)data
                       delegate:(id <TOSMBSessionDeleteTaskDelegate>)delegate {
    if ((self = [super initWithSession:session] )) {
        _sourceFilePath = path;
        self.delegate = delegate;
    }
    
  return nil;
}

- (instancetype)initWithSession:(TOSMBSession *)session
                           path:(NSString *)path
                 successHandler:(id)successHandler
                    failHandler:(id)failHandler{
    if ((self = [super initWithSession:session])) {
        self.session = session;
        _sourceFilePath = path;
        self.successHandler = successHandler;
        self.failHandler = failHandler;
    }
  return self;
}
- (void)performTaskWithOperation:(NSBlockOperation * _Nonnull)weakOperation {
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
  smb_tree_connect(self.smbSession, shareCString, &treeID);
  if (!treeID) {
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
  
  
  //---------------------------------------------------------------------------------------
  //Delete the file handle
  int errorCode = smb_file_rm(self.smbSession, treeID, [formattedPath cStringUsingEncoding:NSUTF8StringEncoding]);
  switch (errorCode) {
    case 0://success
          [self didSucceed];
          break;
    default:
          [self didFailWithError:errorForErrorCode(errorCode)];
      break;
  }
  
  
  if (weakOperation.isCancelled  || self.state != TOSMBSessionTaskStateRunning) {
    self.cleanupBlock(treeID, fileID);
    return;
  }

  self.state = TOSMBSessionTaskStateCompleted;
  
  //Alert the delegate that we finished, so they may perform any additional cleanup operations
//  [self didSucceedWithFilePath:finalDestinationPath];
  
  //Perform a final cleanup of all handles and references
  self.cleanupBlock(treeID, fileID);
}


- (void)didSucceed
{
    __weak typeof(self.delegate) delegate = self.delegate;
    __weak typeof(self) weakSelf = self;
    dispatch_sync(dispatch_get_main_queue(), ^{
        if (delegate && [delegate respondsToSelector:@selector(deleteTaskDidFinish:)]) {
            [delegate deleteTaskDidFinish:weakSelf];
        }
        
        if (weakSelf.successHandler) {
            weakSelf.successHandler();
        }
    });
    
}

- (void)didFailWithError:(NSError *)error
{
    [super didFailWithError:error];
    
    __weak typeof(self.delegate) delegate = self.delegate;
    __weak typeof(self) weakSelf = self;
    dispatch_sync(dispatch_get_main_queue(), ^{
        if (delegate && [delegate respondsToSelector:@selector(deleteTaskDidFinish:)]){
            [delegate deleteTaskDidFinish:weakSelf];
        }

        if (self.failHandler){
            self.failHandler(error);
        }
    });
}


@end
