//
//  FinderSync.m
//  seafile-client-fsplugin
//
//  Created by Chilledheart on 1/10/15.
//  Copyright (c) 2015 Haiwen. All rights reserved.
//

#import "FinderSync.h"
#import "FinderSyncClient.h"
#include <utility>
#include <map>
#include <algorithm>

@interface FinderSync ()

@property(readwrite, nonatomic) FinderSyncClient *client;
@property(readwrite, nonatomic, strong) NSTimer *timer;
@end

@implementation FinderSync

static std::vector<LocalRepo> repos;
static std::map<std::string, std::pair<int, std::vector<NSURL *>>>
    observed_files;
static NSArray *badgeIdentifiers = @[
  @"DISABLED",
  @"WAITING",
  @"INIT",
  @"ING",
  @"DONE",
  @"ERROR",
  @"UNKNOWN"
];

- (instancetype)init {
  self = [super init];

  NSLog(@"%s launched from %@ ; compiled at %s", __PRETTY_FUNCTION__,
        [[NSBundle mainBundle] bundlePath], __TIME__);

  // Set up client
  self.client = new FinderSyncClient(self);
  self.timer =
      [NSTimer scheduledTimerWithTimeInterval:2.0
                                       target:self
                                     selector:@selector(requestUpdateWatchSet)
                                     userInfo:nil
                                      repeats:YES];

  [FIFinderSyncController defaultController].directoryURLs = nil;

  return self;
}

- (void)dealloc {
  delete self.client;
  NSLog(@"%s unloaded ; compiled at %s", __PRETTY_FUNCTION__, __TIME__);
}

#pragma mark - Primary Finder Sync protocol methods

- (void)beginObservingDirectoryAtURL:(NSURL *)url {
  std::string filePath = url.fileSystemRepresentation;

  // find the worktree dir in local repos
  auto posOfLocalRepo = std::find_if(
      repos.begin(), repos.end(), [&](decltype(repos)::value_type &repo) {
        return 0 == strncmp(repo.worktree.c_str(), filePath.c_str(),
                            repo.worktree.size());
      });
  if (posOfLocalRepo == repos.end()) {
    return;
  }

  // insert the node based on worktree dir
  auto posOfObservedFiles = observed_files.find(posOfLocalRepo->worktree);
  if (posOfObservedFiles == observed_files.end()) {
    auto value = decltype(observed_files)::value_type(
        std::move(filePath),
        decltype(observed_files)::mapped_type(posOfLocalRepo->status,
                                              std::vector<NSURL *>()));
    observed_files.emplace(std::move(value));
  }
}

- (void)endObservingDirectoryAtURL:(NSURL *)url {
  std::string filePath = url.fileSystemRepresentation;

  // find the worktree dir in local repos
  auto posOfLocalRepo = std::find_if(
      repos.begin(), repos.end(), [&](decltype(repos)::value_type &repo) {
        return 0 == strncmp(repo.worktree.c_str(), filePath.c_str(),
                            repo.worktree.size());
      });
  if (posOfLocalRepo == repos.end())
    return;

  auto posOfObservedFiles = observed_files.find(posOfLocalRepo->worktree);
  if (posOfObservedFiles == observed_files.end())
    return;

  // only remove the files under the current dir
  auto &filelist = posOfObservedFiles->second.second;
  filelist.erase(
      std::remove_if(filelist.begin(), filelist.end(), [&](NSURL *fileurl) {
        return [url isEqual:[fileurl URLByDeletingLastPathComponent]];
      }), filelist.end());
}

- (void)requestBadgeIdentifierForURL:(NSURL *)url {
  std::string filePath = url.fileSystemRepresentation;

  // find where we have it
  auto pos = std::find_if(
      observed_files.begin(), observed_files.end(),
      [&](decltype(observed_files)::value_type &observed_file) {
        return 0 == strncmp(observed_file.first.c_str(), filePath.c_str(),
                            observed_file.first.size());

      });

  // if not found, unset it
  if (pos == observed_files.end()) {
    [[FIFinderSyncController defaultController] setBadgeIdentifier:@""
                                                            forURL:url];
    return;
  }

  // insert it into observed file list
  pos->second.second.push_back(url);

  // set badge image
  [[FIFinderSyncController defaultController]
      setBadgeIdentifier:badgeIdentifiers[pos->second.first]
                  forURL:url];
}

#pragma mark - Menu and toolbar item support

#if 0
- (NSString *)toolbarItemName {
  return @"Seafile FinderSync";
}

- (NSString *)toolbarItemToolTip {
  return @"Seafile FinderSync: Click the toolbar item for a menu.";
}

- (NSImage *)toolbarItemImage {
  return [NSImage imageNamed:NSImageNameFolder];
}
#endif

- (NSMenu *)menuForMenuKind:(FIMenuKind)whichMenu {
  // Produce a menu for the extension.
  NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
  [menu addItemWithTitle:@"Get Share Link"
                  action:@selector(shareLinkAction:)
           keyEquivalent:@""];

  return menu;
}

- (IBAction)shareLinkAction:(id)sender {
  NSArray *items =
      [[FIFinderSyncController defaultController] selectedItemURLs];
  if (![items count])
    return;
  NSURL *item = items.firstObject;

  std::string fileName = [item fileSystemRepresentation];

  dispatch_async(
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        self.client->doSharedLink(fileName.c_str());
      });
}

- (void)requestUpdateWatchSet {
  dispatch_async(
      dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
        self.client->getWatchSet();
      });
}

- (void)updateWatchSet:(void *)new_repos_ptr {
  std::vector<LocalRepo> new_repos =
      std::move(*static_cast<std::vector<LocalRepo> *>(new_repos_ptr));
  // update repos and observed_files
  // 1. insert new dirs (done by beginObservingDirectoryAtURL auto)
  // 2. remove inexisting dirs (done by endObservingDirectoryAtURL auto)
  // 3. update old dirs and files

  // update old dirs and files
  for (auto &new_repo : new_repos) {
    // if not conflicting, ignore
    if (repos.end() == std::find_if(repos.begin(), repos.end(),
                                    [&](decltype(repos)::value_type &repo) {
                                      return new_repo.worktree == repo.worktree;
                                    }))
      continue;

    // if not found, ignore
    auto pos = observed_files.find(new_repo.worktree);
    if (pos == observed_files.end())
      continue;

    // update old dirs status
    if (pos->second.first == new_repo.status)
      return;
    int new_status = new_repo.status;
    pos->second.first = new_status;

    // update old files status
    for (NSURL *url : pos->second.second) {
      // set badge image
      [[FIFinderSyncController defaultController]
          setBadgeIdentifier:badgeIdentifiers[new_status]
                      forURL:url];
    }
  }

  repos = std::move(new_repos);
  NSMutableArray *array = [NSMutableArray arrayWithCapacity:repos.size()];
  for (const LocalRepo &repo : repos) {
    [array addObject:[NSURL fileURLWithFileSystemRepresentation:repo.worktree
                                                                    .c_str()
                                                    isDirectory:TRUE
                                                  relativeToURL:nil]];
  }

  [FIFinderSyncController defaultController].directoryURLs =
      [NSSet setWithArray:array];

  // initialize the badge images
  static BOOL initialized = FALSE;
  if (!initialized) {
    initialized = TRUE;

    // Set up images for our badge identifiers. For demonstration purposes, this
    // uses off-the-shelf images.
    // DISABLED
    [[FIFinderSyncController defaultController]
             setBadgeImage:[NSImage imageNamed:NSImageNameStatusNone]
                     label:@"Status Disabled"
        forBadgeIdentifier:@"DISABLED"];
    // WAITING,
    [[FIFinderSyncController defaultController]
             setBadgeImage:[NSImage
                               imageNamed:NSImageNameStatusPartiallyAvailable]
                     label:@"Status Waiting"
        forBadgeIdentifier:@"WAITING"];
    // INIT,
    [[FIFinderSyncController defaultController]
             setBadgeImage:[NSImage
                               imageNamed:NSImageNameStatusPartiallyAvailable]
                     label:@"Status Init"
        forBadgeIdentifier:@"INIT"];
    // ING,
    [[FIFinderSyncController defaultController]
             setBadgeImage:[NSImage
                               imageNamed:NSImageNameStatusPartiallyAvailable]
                     label:@"Status Ing"
        forBadgeIdentifier:@"ING"];
    // DONE,
    [[FIFinderSyncController defaultController]
             setBadgeImage:[NSImage imageNamed:NSImageNameStatusAvailable]
                     label:@"Status Done"
        forBadgeIdentifier:@"DONE"];
    // ERROR,
    [[FIFinderSyncController defaultController]
             setBadgeImage:[NSImage imageNamed:NSImageNameCaution]
                     label:@"Status Error"
        forBadgeIdentifier:@"ERROR"];
    // UNKNOWN,
    [[FIFinderSyncController defaultController]
             setBadgeImage:[NSImage imageNamed:NSImageNameStatusNone]
                     label:@"Status Unknown"
        forBadgeIdentifier:@"UNKOWN"];
  }
}

@end
