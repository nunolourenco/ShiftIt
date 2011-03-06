/*
 ShiftIt: Resize windows with Hotkeys
 Copyright (C) 2010  Aravind
 
 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.
 
 */


#import <Foundation/Foundation.h>

/**
 * This unit provides support for sizing application using Apple accessibiity API
 *
 */

@class ShiftItAction;

@interface Screen : NSObject {
 @private
	NSRect visibleFrame_;
	NSRect screenFrame_;
	BOOL primary_;
}

@property (readonly) NSSize size;
@property (readonly) BOOL primary;

@end

typedef void *WindowId;

@interface Window : NSObject {
 @private	
	WindowId ref_;
	NSRect rect_;
	NSRect originalRect_;
	Screen *screen_;
	NSRect drawersRect_;
#ifdef X11
	BOOL x11win_;
	NSRect x11coordRect_;
#endif
}

@property (readonly) NSPoint origin;
@property (readonly) NSSize size;
@property (readonly) Screen *screen;

@end

@interface WindowSizer : NSObject {
 @private
    AXUIElementRef axSystemWideElement_;
	
	int menuBarHeight_;
}


+ (WindowSizer *) sharedWindowSize;

- (void) focusedWindow:(Window **)window error:(NSError **)error;
- (void) shiftWindow:(Window *)window to:(NSPoint)origin size:(NSSize)size screen:(Screen *)screen error:(NSError **)error;

//- (ScreenRef) screenLeftOf:(ScreenRef)screen flipOver:(BOOL)flip;
//- (ScreenRef) screenAbove:(ScreenRef)screen flipOver:(BOOL)flip;
//- (ScreenRef) screenBelow:(ScreenRef)screen flipOver:(BOOL)flip;
//- (ScreenRef) screenRightOf:(ScreenRef)screen flipOver:(BOOL)flip;


@end
