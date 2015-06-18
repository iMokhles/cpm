//
//  CPMDpkgPackageManager.m
//  cpm
//
//  Created by Adam D on 12/05/2015.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import "CPMDpkgPackageManager.h"

@implementation CPMDpkgPackageManager

- (NSString *)name {
	return @"dpkg";
}

- (BOOL)isInstalled {
	return [[NSFileManager defaultManager] fileExistsAtPath:@"/usr/local/bin/dpkg"]; // TODO: this probably shouldn't be hardcoded?
}

- (NSArray *)installedPackages {
	return nil; // TODO: implement
}

- (void)refreshWithParentProgress:(NSProgress *)parentProgress completion:(CPMPackageManagerRefreshCompletion)completion {
	NSProgress *progress = [[NSProgress alloc] initWithParent:parentProgress userInfo:nil];
	progress.totalUnitCount = 100;
	
	progress.completedUnitCount = 100;
	completion(nil); // TODO: implement
}

- (void)packagesForIdentifiers:(NSArray *)identifiers completion:(CPMPackageManagerPackagesForIdentifiersCompletion)completion {
	completion(nil, nil); // TODO: implement
}

- (NSProgress *)package:(id <CPMPackage>)package performOperation:(CPMPackageManagerOperation)operation stateChangeCallback:(CPMPackageManagerStateChangeCallback)stateChangeCallback {
	stateChangeCallback(@"¯\\_(ツ)_/¯", nil); // TODO: implement
	
	NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
	return progress;
}

- (NSString *)packageIdentifierPrefix {
	return nil;
}

- (BOOL)isPrefixCompatible {
	return NO; // TODO: implement
}

- (NSURL *)prefixPath {
	return [NSURL URLWithString:@"file:///"]; // TODO: implement
}

@end
