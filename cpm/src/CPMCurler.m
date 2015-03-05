//
//  CPMCurler.m
//  cpm
//
//  Created by Alexander Zielenski on 3/5/15.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import "CPMCurler.h"
#import "CPDefines.h"

@interface CPMCurler () <NSURLConnectionDelegate, NSURLConnectionDataDelegate> {
    BOOL _executing;
    BOOL _finished;
}
@property (strong) NSURLConnection *connection;
@property (readwrite, copy) NSError *error;
@property (assign) NSInteger expectedLength;
@property (assign) NSInteger currentLength;
@end

@implementation CPMCurler

- (id)initWithURL:(NSURL *)url dataBlock:(void (^)(NSInteger bytesDownloaded, NSInteger bytesExpected, NSData *data))dataBlock completionBlock:(void (^)(void))completion {
    if ((self = [self init])) {
        self.url = url;
        self.completionBlock = completion;
        self.dataBlock = dataBlock;
    }
    
    return self;
}

- (id)init {
    if ((self = [super init])) {
        self.expectedLength = 0;
        self.currentLength = 0;
    }
    
    return self;
}

- (void)start {
    dispatch_sync(dispatch_get_main_queue(), ^{
        self.connection = [[NSURLConnection alloc] initWithRequest:[NSURLRequest requestWithURL:self.url
                                                                                    cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:5]
                                                          delegate:self];
        [self.connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        [self.connection start];
    });
}

- (void)cancel {
    dispatch_sync(dispatch_get_main_queue(), ^{
        [self.connection cancel];
    });
    
    [super cancel];
}

#pragma mark - NSConnectionDelegate

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    self.error = error;
    self.executing = NO;
    self.finished = YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSHTTPURLResponse *)response {
    self.expectedLength = response.expectedContentLength;
    if (response.statusCode != 200) {
        self.error = [NSError errorWithDomain:CPMERRORDOMAIN
                                         code:CPMErrorUnacceptableStatusCode
                                     userInfo:@{NSLocalizedFailureReasonErrorKey: @"Bad Status Code",
                                                CPMErrorStatusCodeKey: @(response.statusCode)}];
        [self.connection cancel];
        self.executing = NO;
        self.finished = YES;
    }
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    self.executing = NO;
    self.finished = YES;
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    self.currentLength += data.length;
    if (self.dataBlock)
        self.dataBlock(self.currentLength, self.expectedLength, data);
}

#pragma mark - NSOperation Properties

- (BOOL)isAsynchronous {
    return YES;
}

- (BOOL)isConcurrent {
    return YES;
}

- (BOOL)isReady {
    return super.isReady && self.url;
}

- (void)setExecuting:(BOOL)executing {
    [self willChangeValueForKey:@"executing"];
    _executing = executing;
    [self didChangeValueForKey:@"executing"];
}

- (void)setFinished:(BOOL)finished {
    [self willChangeValueForKey:@"finished"];
    _finished = finished;
    [self didChangeValueForKey:@"finished"];
}

- (BOOL)isExecuting {
    return _executing;
}

- (BOOL)isFinished {
    return _finished;
}

@end
