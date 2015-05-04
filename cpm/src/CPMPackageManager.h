//
//  CPMPackageManager.h
//  cpm
//
//  Created by Adam D on 5/05/2015.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "CPMPackage.h"

typedef NS_ENUM(NSUInteger, CPMPackageManagerOperation) {
	CPMPackageManagerOperationInstall,
	CPMPackageManagerOperationReinstall,
	CPMPackageManagerOperationRemove,
	CPMPackageManagerOperationUpgrade
};

typedef void (^CPMPackageManagerRefreshCompletion)(NSError *error);

@protocol CPMPackageManager <NSObject>

@required

// Human readable name of the package manager.
- (NSString *)name;

// Whether it's installed or not.
- (BOOL)isInstalled;

// Packages installed from this package manager.
- (NSArray *)installedPackages;

// Refresh packages and call the completion with the error or nil.
- (void)refreshWithCompletion:(CPMPackageManagerRefreshCompletion)completion;

// Retrieve package model object.
- (CPMPackage *)packageForIdentifier:(NSString *)identifier;

// Perform an operation on a package.
- (void)package:(id <CPMPackage>)package performOperation:(CPMPackageManagerOperation)operation completion:(CPMPackageManagerOperationCompletion)completion;

@optional

// Prefix used to make the package manager compatible with others.
- (NSString *)packageIdentifierPrefix;

// Whether it supports installing to a prefix (e.g., home directory).
- (BOOL)isPrefixCompatible;

// Path to the prefix, if the above returns YES.
- (NSURL *)prefixPath;

@end
