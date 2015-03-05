//
//  CPRepository.m
//  cpm
//
//  Created by Alexander Zielenski on 3/2/15.
//  Copyright (c) 2015 Chariz Team. All rights reserved.
//
// https://wiki.debian.org/RepositoryFormat#Types_of_files

#import "CPRepository.h"
#import "CPDefines.h"

typedef NS_ENUM(NSUInteger, CPRepositoryIndexCompression) {
    CPRepositoryIndexCompressionLZMA,
    CPRepositoryIndexCompressionXZ,
    CPRepositoryIndexCompressionLZIP,
    CPRepositoryIndexCompressionBzip2,
    CPRepositoryIndexCompressionGzip2,
    CPRepositoryIndexCompressionNone
};

NSString *extensionForCompression(CPRepositoryIndexCompression compression) {
    switch (compression) {
        case CPRepositoryIndexCompressionBzip2:
            return @"bz2";
        case CPRepositoryIndexCompressionGzip2:
            return @"gz";
        case CPRepositoryIndexCompressionLZMA:
            return @"lzma";
        case CPRepositoryIndexCompressionLZIP:
            return @"lz";
        case CPRepositoryIndexCompressionXZ:
            return @"xz";
        case CPRepositoryIndexCompressionNone:
        default:
            return @"";
    }
    
    return @"";
}

NSString *baseify(NSURL *url) {
    NSString *scheme = url.scheme;
    NSString *substr = [url.absoluteString substringFromIndex:scheme.length + 3]; /* :// */
    return [[substr stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@":" withString:@"@"];
}

NSDictionary *dictionarize(NSString *data) {
    NSArray *components = [data componentsSeparatedByString:@"\n"];
    NSMutableDictionary *values = [NSMutableDictionary dictionary];
    
    for (NSString *segment in components) {
        NSRange keyRange = [segment rangeOfString:@":"];
        if (keyRange.location == NSNotFound) {
            continue;
        }
        
        NSString *key = [segment substringToIndex:keyRange.location].lowercaseString;
        key = [key stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
        
        NSString *value = [segment substringFromIndex:keyRange.location + keyRange.length];
        value = [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
        values[key] = value;
    }
    
    return values;
}

NSString *argumentsForUpdateDictionary(NSDictionary *dict) {
    // returns in the format (keys) values (:values)
    return [NSString stringWithFormat:@"(%@) values (:%@)", [dict.allKeys componentsJoinedByString:@", "], [dict.allKeys componentsJoinedByString:@", :"]];
}

NSString *decompress(NSData *data) {
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

@interface CPRepository () <NSURLConnectionDelegate, NSURLConnectionDataDelegate>
@property (readwrite, strong) NSURL *url;
@property (strong) NSMutableData *releaseData;
@property (strong) NSMutableData *sourcesData;
@property (strong) NSOperationQueue *queue;
@property (strong) NSString *lastPackageSegment;
@property (readwrite, strong) NSMutableArray *packages;
- (void)obtainIndices;
- (void)obtainReleaseIndexWithCompression:(CPRepositoryIndexCompression)compression;
@end

@implementation CPRepository

+ (instancetype)repositoryWithURL:(NSURL *)url {
    return [[self alloc] initWithURL:url];
}

- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        self.queue = [[NSOperationQueue alloc] init];
        self.queue.maxConcurrentOperationCount = 1;
        self.url = url;
        self.packages = [NSMutableArray array];
        
        [[NSFileManager defaultManager] createDirectoryAtPath:LOCALSTORAGE_PATH
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
        
        // Generate database path for this url:
        NSString *dbPath = [LOCALSTORAGE_PATH stringByAppendingPathComponent:baseify(self.url)];
        self.database = [FMDatabase databaseWithPath:dbPath];
        if (![self.database open]) {
            //!TODO: error
            NSLog(@"couldnt open database for writing");
            return nil;
        }
        
    }
    
    return self;
}

- (void)reloadData {
    [self.database executeUpdate:@"drop table release"];
    [self.database executeUpdate:@"create table release (architectures text, codename text, components text, description text, label text, suite text, version text, origin text)"];
    [self.database executeUpdate:@"create table packages (package text primary key, size integer, version text, filename text, architecture text, maintainer text, installed_size integer, depends text, md5sum text, sha1 text, sha256 text, section text, priority text, homepage text, description text, author text, depiction text, sponsor text, icon text, name text)"];
    
    [self obtainIndices];
}

- (void)dealloc {
    [self.database close];
}

// Release, Packages, Sources
//!TODO: Implement HTTP authentication or make the user put it into the url
- (void)obtainIndices {
    [self obtainReleaseIndexWithCompression:CPRepositoryIndexCompressionNone];
    [self obtainPackagesIndexWithCompression:CPRepositoryIndexCompressionNone];
}

- (void)obtainPackagesIndexWithCompression:(CPRepositoryIndexCompression)compression {
    if (compression > CPRepositoryIndexCompressionNone) {
        // error...
        return;
    }
    
    NSURL *packagesURL = [self.url URLByAppendingPathComponent:@"Packages"];
    NSString *ext = extensionForCompression(compression);
    if (ext.length > 0) {
        packagesURL = [packagesURL URLByAppendingPathExtension:ext];
    }
    
    
    NSURLConnection *connection = [[NSURLConnection alloc] initWithRequest:[NSURLRequest requestWithURL:packagesURL cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData timeoutInterval:5]
                                                                  delegate:self
                                                          startImmediately:YES];
    [connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)obtainReleaseIndexWithCompression:(CPRepositoryIndexCompression)compression {
    if (compression > CPRepositoryIndexCompressionNone) {
        // error...
        return;
    }
    
    NSURL *releaseURL = [self.url URLByAppendingPathComponent:@"Release"];
    NSString *ext = extensionForCompression(compression);
    if (ext.length > 0) {
        releaseURL = [releaseURL URLByAppendingPathExtension:ext];
    }
    
    __weak CPRepository *weakSelf = self;
    [NSURLConnection sendAsynchronousRequest:[NSURLRequest requestWithURL:releaseURL
                                                              cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                          timeoutInterval:5]
                                       queue:self.queue
                           completionHandler:^(NSURLResponse *response, NSData *data, NSError *connectionError) {
                               // if we could not find the file, progress through each supported compression format until we get a match
                               if (connectionError) {
                                   return [weakSelf obtainReleaseIndexWithCompression:compression + 1];
                               } else if (data) {
                                   NSString *strRep = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                                   NSLog(@"%@", dictionarize(strRep));
                                   [self.database executeUpdate:@"insert into release values (:architectures, :codename, :components, :description, :label, :suite, :version, :origin)" withParameterDictionary:dictionarize(strRep)];
                               }
                           }];
}

- (NSArray *)listPackages {
    FMResultSet *results = [self.database executeQuery:@"select package, name, description, icon, version, section from packages"];
    NSMutableArray *list = [NSMutableArray array];
    NSDictionary *map = results.columnNameToIndexMap;
    while ([results next]) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        for (NSString *key in map) {
            id value = [results objectForColumnName:key];
            if (value && ![value isKindOfClass:[NSNull class]]) {
                dict[key] = value;
            }
        }
        
        [list addObject:dict];
    }
    
    [self downloadPackage:@"com.alexzielenski.zeppelin"];
    return list;
}

- (NSArray *)searchForPackage:(NSString *)input {
    NSString *query = [NSString stringWithFormat:@"select package, name, description, icon, version, section from packages where name like '%%%@%%' limit 1", input];
    FMResultSet *results = [self.database executeQuery:query];
    NSMutableArray *list = [NSMutableArray array];
    NSDictionary *map = results.columnNameToIndexMap;
    while ([results next]) {
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        for (NSString *key in map) {
            id value = [results objectForColumnName:key];
            if (value && ![value isKindOfClass:[NSNull class]]) {
                dict[key] = value;
            }
        }
        
        [list addObject:dict];
    }
    return list;
}

- (NSURL *)downloadPackage:(NSString *)identifier {
    NSString *query = [NSString stringWithFormat:@"select package, filename from packages where package is '%@'", identifier];
    FMResultSet *results = [self.database executeQuery:query];
    [results next];
    if (results.hasAnotherRow) {
        NSLog(@"too many items with the same identifier");
        return nil;
    }

    NSURL *remoteURL = [self.url URLByAppendingPathComponent:[results stringForColumn:@"filename"]];
    NSLog(@"%@", remoteURL);
    NSURL *localURL = [NSURL fileURLWithPath:[[NSTemporaryDirectory() stringByAppendingPathComponent:IDENTIFIER] stringByAppendingPathComponent:remoteURL.lastPathComponent]];
    [[NSFileManager defaultManager] createDirectoryAtURL:localURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    
    return localURL;
}

#pragma mark - NSURLConnectionDelegate

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
//    NSString *path = [[NSTemporaryDirectory() stringByAppendingPathComponent:@"io.chariz.cpm"] stringByAppendingFormat:@"/%@_Packages", self.url.host];
//
//    [[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent
//                              withIntermediateDirectories:YES
//                                               attributes:nil
//                                                    error:nil];
//    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    // Parse this now and wait for the next portion of the file
    __weak CPRepository *weakSelf = self;
    [self.queue addOperationWithBlock:^{
        NSString *package = decompress(data);
        if (weakSelf.lastPackageSegment) {
            package = [weakSelf.lastPackageSegment stringByAppendingString:package];
        }
        weakSelf.lastPackageSegment = nil;
        
        NSArray *segments = [package componentsSeparatedByString:@"\n\n"];
        weakSelf.lastPackageSegment = segments.lastObject;
        for (NSUInteger x = 0; x < segments.count - 1; x++) {
            NSString *segment = segments[x];
            NSDictionary *dict = dictionarize(segment);
            NSString *query = [NSString stringWithFormat:@"insert or replace into packages (%@) values (:%@)",
                               [dict.allKeys componentsJoinedByString:@", "],
                               [dict.allKeys componentsJoinedByString:@", :"]];
            [weakSelf.database executeUpdate:query withParameterDictionary:dict];
        }
    }];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    __weak CPRepository *weakSelf = self;
    [self.queue addOperationWithBlock:^{
        NSDictionary *dict = dictionarize(weakSelf.lastPackageSegment);
        if ([dict.allKeys containsObject:@"package"]) {
            NSString *query = [NSString stringWithFormat:@"insert or replace into packages (%@) values (:%@)",
                               [dict.allKeys componentsJoinedByString:@", "],
                               [dict.allKeys componentsJoinedByString:@", :"]];
            [weakSelf.database executeUpdate:query withParameterDictionary:dict];
        }
        
        weakSelf.lastPackageSegment = nil;
    }];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    //!TODO retry with diff compression extension until we cant try no more
}

@end