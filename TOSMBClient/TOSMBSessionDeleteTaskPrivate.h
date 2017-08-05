//
//  TOSMBSessionDeleteTaskPrivate.h
//  Pods
//
//  Created by Albert Park on 8/5/17.
//

#ifndef TOSMBSessionDeleteTaskPrivate_h
#define TOSMBSessionDeleteTaskPrivate_h

#import "TOSMBSessionDeleteTask.h"
#import "TOSMBSessionTaskPrivate.h"

@interface TOSMBSessionDeleteTask()<TOSMBSessionConcreteTask>

- (instancetype)initWithSession:(TOSMBSession *)session
                           path:(NSString *)path
                           data:(NSData *)data
                       delegate:(id <TOSMBSessionDeleteTaskDelegate>)delegate;

- (instancetype)initWithSession:(TOSMBSession *)session
                           path:(NSString *)path
                 successHandler:(id)successHandler
                    failHandler:(id)failHandler;


@end

#endif /* TOSMBSessionDeleteTaskPrivate_h */
