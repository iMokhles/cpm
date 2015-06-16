//
//  CPMPackageManagerAggregate.h
//  
//
//  Created by Adam D on 15/06/2015.
//
//

#import <Foundation/Foundation.h>
#import "CPMPackageManager.h"

@interface CPMPackageManagerAggregate : NSObject

+ (instancetype)sharedInstance;

- (NSArray *)installedPackages;
- (void)refreshWithCompletion:(CPMPackageManagerRefreshCompletion)completion;
- (void)packagesForIdentifiers:(NSArray *)identifiers completion:(CPMPackageManagerPackagesForIdentifiersCompletion)completion;
- (NSProgress *)package:(id <CPMPackage>)package performOperation:(CPMPackageManagerOperation)operation stateChangeCallback:(CPMPackageManagerStateChangeCallback)stateChangeCallback;

@end
