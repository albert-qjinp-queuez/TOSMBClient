//
//  TOSMBSessionDeleteTask.h
//  TOSMBClient
//
//  Created by Albert Park on 8/5/17.
//

#import "TOSMBSessionTask.h"

@class TOSMBSessionDeleteTask;

@protocol TOSMBSessionDeleteTaskDelegate <TOSMBSessionTaskDelegate>
@optional

- (void)deleteTaskDidFinish:(TOSMBSessionDeleteTask *)task;

@end

@interface TOSMBSessionDeleteTask : TOSMBSessionTask

@end
