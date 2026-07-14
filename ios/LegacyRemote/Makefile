TARGET := iphone:clang:latest:6.0
ARCHS := armv7

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = VibeSlopik

VibeSlopik_FILES = main.m VSAppDelegate.m VSSettingsViewController.m VSSessionsViewController.m VSProjectViewController.m VSChoiceViewController.m VSChatViewController.m VSBridgeClient.m VSDraftStore.m VSMediaCache.m VSImageViewController.m VSLocalization.m
VibeSlopik_FRAMEWORKS = UIKit Foundation QuartzCore CoreGraphics AVFoundation
VibeSlopik_CFLAGS = -fblocks

include $(THEOS_MAKE_PATH)/application.mk
