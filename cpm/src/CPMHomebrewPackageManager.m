//
//  CPMHomebrewPackageManager.m
//  cpm
//
//  Created by Adam D on 12/05/2015.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import "CPMHomebrewPackageManager.h"
#import "CPMHomebrewPackage.h"

typedef void (^CPMHomebrewTaskCompletion)(NSError *error, id json, NSString *output, NSString *errorOutput);

static NSString *const kCPMHomebrewPackageManagerDefaultURL = @"file:///usr/local/";
static NSString *const kCPMHomebrewBrewCommandPath = @"bin/brew";

@implementation CPMHomebrewPackageManager

- (NSString *)name {
	return @"Homebrew";
}

- (BOOL)isInstalled {
	BOOL isDirectory;
	BOOL dirExists = [[NSFileManager defaultManager] fileExistsAtPath:self.prefixPath.path isDirectory:&isDirectory];
	
	return dirExists && isDirectory;
}

- (NSArray *)installedPackages {
	// TODO: should this be async using brew --json=v1 --installed?
	NSDirectoryEnumerator *directoryEnumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL URLWithString:@"Cellar" relativeToURL:self.prefixPath].URLByResolvingSymlinksInPath includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler:^BOOL(NSURL *url, NSError *error) {
		NSLog(@"homebrew: warning: failed to read directory %@: %@", url, error);
		return YES;
	}];
	
	NSMutableArray *packages = [NSMutableArray array];
	NSURL *url = nil;
	
	while ((url = directoryEnumerator.nextObject)) {
		[packages addObject:url.lastPathComponent];
	}
	
	return packages;
}

- (void)refreshWithParentProgress:(NSProgress *)parentProgress completion:(CPMPackageManagerRefreshCompletion)completion {
	NSProgress *progress = [[NSProgress alloc] initWithParent:parentProgress userInfo:nil];
	progress.totalUnitCount = 100;
	
	// TODO: to display progress, we might need to reimplement this natively
	// that seems like a risky decision to make in case homebrew makes a breaking change, however
	[self _launchBrewTaskWithArguments:@[ @"update" ] completion:^(NSError *error, id json, NSString *output, NSString *errorOutput) {
		progress.completedUnitCount = 100;
		completion(error);
	}];
}

- (void)packagesForIdentifiers:(NSArray *)identifiers completion:(CPMPackageManagerPackagesForIdentifiersCompletion)completion {
	[self _launchBrewTaskWithArguments:[@[ @"info", @"--json=v1" ] arrayByAddingObjectsFromArray:identifiers] completion:^(NSError *error, id json, NSString *output, NSString *errorOutput) {
		if (error) {
			completion(nil, error);
			return;
		}
		
		NSMutableDictionary *packages = [NSMutableDictionary dictionary];
		
		for (NSDictionary *package in json) {
			packages[package[@"full_name"]] = [[CPMHomebrewPackage alloc] initWithDictionary:package];
		}
	}];
}

- (NSProgress *)package:(CPMHomebrewPackage *)package performOperation:(CPMPackageManagerOperation)operation stateChangeCallback:(CPMPackageManagerStateChangeCallback)stateChangeCallback {
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
	return [NSURL URLWithString:kCPMHomebrewPackageManagerDefaultURL]; // TODO: implement
}

#pragma mark - Tasks

- (void)_launchBrewTaskWithArguments:(NSArray *)arguments completion:(CPMHomebrewTaskCompletion)completion {
	NSTask *task = [[NSTask alloc] init];
	task.launchPath = [self.prefixPath.path stringByAppendingPathComponent:kCPMHomebrewBrewCommandPath];
	task.arguments = arguments;
	task.standardOutput = [NSPipe pipe];
	task.standardError = [NSPipe pipe];
	task.terminationHandler = ^(NSTask *task) {
		NSError *error = nil;
		
		if (task.terminationStatus) {
			error = [NSError errorWithDomain:CPMHomebrewErrorDomain code:task.terminationStatus userInfo:@{
				NSLocalizedDescriptionKey: [NSString stringWithFormat:@"The Homebrew package manager returned an error with code %d.", task.terminationStatus]
			}];
		}
		
		NSData *outputData = ((NSPipe *)task.standardOutput).fileHandleForReading.readDataToEndOfFile;
		id json = nil;
		
		if (outputData.length > 0) {
			char firstByte[1];
			
			[outputData getBytes:&firstByte range:NSMakeRange(0, 1)];
			
			if (firstByte && (firstByte[0] == '{' || firstByte[0] == '[')) {
				json = [NSJSONSerialization JSONObjectWithData:outputData options:kNilOptions error:&error];
			}
		}
		
		NSString *output = nil;
		
		if (!json) {
			output = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding];
		}
		
		NSString *errorOutput = [[NSString alloc] initWithData:((NSPipe *)task.standardError).fileHandleForReading.readDataToEndOfFile encoding:NSUTF8StringEncoding];
		
		completion(error, json, output, errorOutput);
	};
	
	[task launch];
}

@end
