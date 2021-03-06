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
	CPMPackageManagerOperationDownload,
	CPMPackageManagerOperationInstall,
	CPMPackageManagerOperationReinstall,
	CPMPackageManagerOperationRemove,
	CPMPackageManagerOperationUpgrade
};

typedef void (^CPMPackageManagerRefreshCompletion)(NSError *error);
typedef void (^CPMPackageManagerStateChangeCallback)(NSString *logMessage, NSError *error);
typedef void (^CPMPackageManagerPackagesForIdentifiersCompletion)(NSDictionary *packages, NSError *error);

@protocol CPMPackageManager <NSObject>

@required

// Human readable name of the package manager.
- (NSString *)name;

// Whether it's installed or not.
- (BOOL)isInstalled;

// Packages installed from this package manager.
- (NSArray *)installedPackages;

// Refresh packages and call the completion with the error or nil.
- (void)refreshWithParentProgress:(NSProgress *)parentProgress completion:(CPMPackageManagerRefreshCompletion)completion;

// Retrieve package model object.
- (void)packagesForIdentifiers:(NSArray *)identifiers completion:(CPMPackageManagerPackagesForIdentifiersCompletion)completion;

// Perform an operation on a package.
- (NSProgress *)package:(id <CPMPackage>)package performOperation:(CPMPackageManagerOperation)operation stateChangeCallback:(CPMPackageManagerStateChangeCallback)stateChangeCallback;

@optional

// Prefix used to make the package manager compatible with others.
- (NSString *)packageIdentifierPrefix;

// Whether it supports installing to a prefix (e.g., home directory).
- (BOOL)isPrefixCompatible;

// Path to the prefix, if the above returns YES.
- (NSURL *)prefixPath;

@end
