//
//  TOSMBSessionReadTask.h
//  libchardet
//
//  Created by Albert Park on 4/21/18.
//

#import "TOSMBSessionTask.h"
#import "TOSMBConstants.h"

@class TOSMBSession;
@class TOSMBSessionReadTask;


@protocol TOSMBSessionReadTaskDelegate <TOSMBSessionTaskDelegate>

@optional

/**
 Delegate event that is called when the file has successfully completed downloading and was moved to its final destionation.
 If there was a file with the same name in the destination, the name of this file will be modified and this will be reflected in the
 `destinationPath` value
 
 @param readTask The download task object calling this delegaxte method.
 @param data data collected
 */
- (void)readTask:(TOSMBSessionReadTask *)readTask didFinishDownloadingForData:(NSData *)data;

/**
 Delegate event that is called periodically as the download progresses, updating the delegate with the amount of data that has been downloaded.
 
 @param readTask The download task object calling this delegate method.
 @param bytesWritten The number of bytes written in this particular iteration
 @param totalBytesReceived The total number of bytes written to disk so far
 @param totalBytesToReceive The expected number of bytes encompassing this entire file
 */
- (void)readTask:(TOSMBSessionReadTask *)readTask
       didWriteBytes:(uint64_t)bytesWritten
  totalBytesReceived:(uint64_t)totalBytesReceived
totalBytesExpectedToReceive:(int64_t)totalBytesToReceive;

/**
 Delegate event that is called when a file download that was previously suspended is now resumed.
 
 @param readTask The download task object calling this delegate method.
 @param byteOffset The byte offset at which the download resumed.
 @param totalBytesToReceive The number of bytes expected to write for this entire file.
 */
- (void)readTask:(TOSMBSessionReadTask *)readTask
   didResumeAtOffset:(uint64_t)byteOffset
totalBytesExpectedToReceive:(uint64_t)totalBytesToReceive;

/**
 Delegate event that is called when the file did not successfully complete.
 
 @param readTask The download task object calling this delegate method.
 @param error The error describing why the task failed.
 */
- (void)readTask:(TOSMBSessionReadTask *)readTask didCompleteWithError:(NSError *)error __deprecated_msg("See -task:didCompleteWithError:");

@end

@interface TOSMBSessionReadTask : TOSMBSessionTask

/** The file path to the target file on the SMB network device. */
@property (readonly) NSString *sourceFilePath;

/** The data from the file readed. */
@property (readonly) NSData *data;

/** The number of bytes presently downloaded by this task */
@property (readonly) int64_t countOfBytesReceived;

/** The total number of bytes we expect to download */
@property (readonly) int64_t countOfBytesExpectedToReceive;

@end
