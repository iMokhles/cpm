//
//  CPMPackageManagerAggregate.h
//  
//
//  Created by Adam D on 15/06/2015.
//
//

#import <Foundation/Foundation.h>
#import "CPMPackageManager.h"

typedef void (^CPMPackageManagerAggregateRefreshCompletion)(NSArray *errors);

@interface CPMPackageManagerAggregate : NSObject

+ (instancetype)sharedInstance;

- (NSArray *)installedPackages;
- (NSProgress *)refreshWithCompletion:(CPMPackageManagerAggregateRefreshCompletion)completion;
- (void)packagesForIdentifiers:(NSArray *)identifiers completion:(CPMPackageManagerPackagesForIdentifiersCompletion)completion;
- (NSProgress *)package:(id <CPMPackage>)package performOperation:(CPMPackageManagerOperation)operation stateChangeCallback:(CPMPackageManagerStateChangeCallback)stateChangeCallback;

@end
