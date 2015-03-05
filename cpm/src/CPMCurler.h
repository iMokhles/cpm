//
//  CPMCurler.h
//  cpm
//
//  Created by Alexander Zielenski on 3/5/15.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CPMCurler : NSOperation
@property (copy) NSURL *url;
@property (copy) void (^dataBlock)(NSInteger bytesDownloaded, NSInteger bytesExpected, NSData *data);
@property (readonly, copy) NSError *error;
@property (readonly, strong) NSData *data;

- (id)initWithURL:(NSURL *)url dataBlock:(void (^)(NSInteger bytesDownloaded, NSInteger bytesExpected, NSData *data))dataBlock completionBlock:(void (^)(void))completion;

@end
