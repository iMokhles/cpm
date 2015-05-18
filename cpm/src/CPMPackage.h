//
//  CPMPackage.h
//  cpm
//
//  Created by Adam D on 5/05/2015.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSUInteger, CPMPackageState) {
	CPMPackageStateNone,
	CPMPackageStateBroken,
	CPMPackageStateInstalled,
	CPMPackageStateWillInstall,
	CPMPackageStateRemoved,
	CPMPackageStateWillRemove
};

// https://www.debian.org/doc/debian-policy/ch-archive.html#s-priorities
typedef NS_ENUM(NSUInteger, CPMPackagePriority) {
	CPMPackagePriorityOptional,
	CPMPackagePriorityRequired,
	CPMPackagePriorityImportant
};

@protocol CPMPackage <NSObject>

@required

#pragma mark - General

// Package's unique identifier.
- (NSString *)identifier;

// State of the package on this computer.
- (CPMPackageState)state;

// Architecture the package is for. "all" if CPU independent.
- (NSString *)architecture;

// Name of the maintainer.
- (NSString *)maintainerName;

// Email address of the maintainer.
- (NSString *)maintainerEmailAddress;

// Section name that the package falls under, or nil.
- (NSString *)section;

// File to download.
- (NSURL *)downloadURL;

// Raw package information in a dpkg compatible key-value format.
- (NSDictionary *)rawFields;

#pragma mark - Relationships

// https://www.debian.org/doc/debian-policy/ch-relationships.html

// Packages this package requires.
- (NSArray *)depends;

// Packages this package requires before installation can occur.
- (NSArray *)preDepends;

// Optional add-ons to this package. Installed by default.
- (NSArray *)recommends;

// Optional add-ons to this package. Not installed by default.
- (NSArray *)suggests;

// Packages this package enhances.
- (NSArray *)enhances;

// Packages this package breaks.
- (NSArray *)breaks;

// Packages this package conflicts with.
- (NSArray *)conflicts;

// Virtual package identifiers this package provides.
- (NSArray *)provides;

// Package identifiers this package replaces.
- (NSArray *)replaces;

@optional

#pragma mark - URLs

// Package website URL.
- (NSURL *)websiteURL;

// Support URL.
- (NSURL *)supportURL;

// Depiction URL for displaying custom UI in a package manager GUI.
- (NSURL *)depictionURL;

#pragma mark - Non-required general

// Name of the author, if different from the maintainer.
- (NSString *)authorName;

// Email address of the author.
- (NSString *)authorEmailAddress;

// Name of the uploader that hosts the package.
// TODO: a separate field for the uploader may be introducing too much complexity
- (NSString *)uploaderName;

// Email address of the uploader.
- (NSString *)uploaderEmailAddress;

// Whether the package requires compilation.
- (BOOL)requiresCompilation;

// A warning to be displayed to the user when installing, or nil if none.
- (NSString *)installationWarnings;

@end
