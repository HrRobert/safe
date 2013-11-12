//
//  LBXMountLockboxWindowController.m
//  Lockbox
//
//  Created by Rian Hunter on 11/8/13.
//  Copyright (c) 2013 Rian Hunter. All rights reserved.
//

#import <lockbox/LBXMountLockboxWindowController.h>

#import <lockbox/LBXProgressSheetController.h>

#import <lockbox/logging.h>

@interface LBXMountLockboxWindowController ()

@end

@implementation LBXMountLockboxWindowController

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    return self;
}

- (id)initWithDelegate:(NSObject <LBXMountLockboxWindowControllerDelegate> *) del
                    fs:(std::shared_ptr<encfs::FsIO>)fs_
               fileURL:(NSURL *)fileURL {
    NSLog(@"sup start");
    
    self = [self initWithWindowNibName:@"LBXMountLockboxWindowController"];
    if (self) {
        self.delegate = del;
        self->fs = fs_;
        
        // load window
        (void) self.window;
        
        if (!fileURL) fileURL = [NSURL fileURLWithPath:NSHomeDirectory()];
        self.locationPathControl.URL = fileURL;
        
        self.window.canHide = NO;
        [self.window center];
        [self.window makeKeyAndOrderFront:self];
        self.window.level = NSModalPanelWindowLevel;
        self.window.delegate = self;
    }
    
    return self;
}

- (id)initWithDelegate:(NSObject <LBXMountLockboxWindowControllerDelegate> *) del
                    fs:(std::shared_ptr<encfs::FsIO>)fs_ {
    return [self initWithDelegate:del
                               fs:fs_
                          fileURL:nil];
    
}

- (id)initWithDelegate:(NSObject <LBXMountLockboxWindowControllerDelegate> *) del
                    fs:(std::shared_ptr<encfs::FsIO>)fs_
                  path:(encfs::Path)p {
    return [self initWithDelegate:del
                               fs:fs_
                          fileURL:[NSURL fileURLWithPath:[NSString stringWithUTF8String:p.c_str()]]];
}

- (void)windowWillClose:(NSNotification *)notification {
    (void) notification;
    [self.window orderOut:self];
    [self.delegate startLockboxCanceled:self];
}

- (IBAction)confirmStart:(id)sender {
    (void) sender;
    
    encfs::SecureMem password([self.passwordSecureTextField.stringValue lengthOfBytesUsingEncoding:NSUTF8StringEncoding] + 1);
    memcpy(password.data(),
           self.passwordSecureTextField.stringValue.UTF8String,
           password.size());
    
    opt::optional<encfs::Path> maybeLocationPath;
    try {
        maybeLocationPath = self->fs->pathFromString(self.locationPathControl.URL.path.UTF8String);
    }
    catch (...) {
        inputErrorAlert(self.window, @"Bad Location",
                        @"The location you chose is not a valid path.");
        return;
    }
    
    auto encrypted_container_path = *maybeLocationPath;
    
    bool is_dir = false;
    try {
        is_dir = encfs::is_directory(self->fs, encrypted_container_path);
    }
    catch (...) {
        // TODO: log error?
    }
    
    if (!is_dir) {
        inputErrorAlert(self.window, @"Bad Location",
                        @"The location you chose is not a folder.");
        return;
    }
    
    auto onFail = ^(const std::exception_ptr & eptr) {
        bool alerted = false;
        if (eptr != std::exception_ptr()) {
            try {
                std::rethrow_exception(eptr);
            }
            catch (const encfs::ConfigurationFileDoesNotExist & /*err*/) {
                inputErrorAlert(self.window,
                                @"Not a Bitvault",
                                [NSString stringWithFormat:@"The location you selected, \"%s\", is not a Bitvault.",
                                 encrypted_container_path.c_str(), nil]);
                alerted = true;
            }
            catch (const std::exception &err) {
                lbx_log_error("Error while mounting: %s", err.what());
            }
        }
        
        if (!alerted) {
            inputErrorAlert(self.window,
                            @"Unknown Error",
                            @"Unknown error occurred while starting the Bitvault.");
        }
    };
    
    auto onMountSuccess = ^(lockbox::mac::MountDetails md) {
        [self.delegate startLockboxDone:self mount:std::move(md)];
        [self.window performClose:self];
    };
    
    auto onVerifySuccess = ^(opt::optional<encfs::EncfsConfig> maybeConfig) {
        if (maybeConfig) {
            // success pass values to app
            showBlockingSheetMessage(self.window,
                                     @"Mounting Existing Bitvault...",
                                     onMountSuccess,
                                     onFail,
                                     lockbox::mac::mount_new_encfs_drive,
                                     self->fs,
                                     encrypted_container_path, *maybeConfig, password);
        }
        else {
            inputErrorAlert(self.window,
                            @"Password is Incorrect",
                            @"The password you have entered is incorrect.");
        }
    };
    
    auto onReadCfgSuccess = ^(encfs::EncfsConfig cfg) {
        showBlockingSheetMessage(self.window,
                                 @"Verifying Bitvault password...",
                                 onVerifySuccess,
                                 onFail,
                                 ^{
                                     auto pass_is_correct = encfs::verify_password(cfg, password);
                                     return (pass_is_correct
                                             ? opt::make_optional(cfg)
                                             : opt::nullopt);
                                 });
    };
    
    showBlockingSheetMessage(self.window,
                             @"Reading Bitvault configuration...",
                             onReadCfgSuccess,
                             onFail,
                             encfs::read_config, self->fs, encrypted_container_path);
}

- (IBAction)cancelStart:(id)sender {
    [self.window performClose:sender];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

@end
