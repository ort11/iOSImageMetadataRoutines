//
//  iOSImageMetaDataRoutines.m
//  iOSImageMetaDataRoutines
//
//  Created by Orthober, Jeffry on 1/23/14.
//  Copyright (c) 2014 jjjconsulting. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "iOSImageMetaDataRoutines.h"

#import <AssetsLibrary/AssetsLibrary.h>
#import <ImageIO/ImageIO.h>

@implementation iOSImageMetaDataRoutines

/// \brief will copy the image from the source to the documents directory
///
/// The copy needs to be done to allow for image Meta Data to be sent with the email.
/// Images attached from the photo library to email loose the meta data (thanks Apple).
/// Once the images are copied to the documents directory, GPS information can be obtained
/// AND stored to the image file / data and then sent via email.
///
/// \param[in] fileURL, the url of the file to be copied
/// \param[in] destinationFullFilePath, the full path for the file to be copied to
///
- (void) copyFileWithUrl: (NSURL *) urlFile destinationFullFilePath: (NSString *) stringDestinationFullFilePath {
    ALAssetsLibrary *assetLibrary = [[ALAssetsLibrary alloc] init];
    [assetLibrary assetForURL: urlFile resultBlock: ^(ALAsset *asset)
     {
         ALAssetRepresentation *rep = [asset defaultRepresentation];
         Byte *buffer = (Byte *) malloc(rep.size);
         NSUInteger buffered = [rep getBytes: buffer fromOffset: 0 length: rep.size error: nil];
         NSData *data = [NSData dataWithBytesNoCopy: buffer length: buffered freeWhenDone: YES];
         [data writeToFile: stringDestinationFullFilePath atomically: YES];
         
         [self continueAfterImageFileCopy: stringDestinationFullFilePath];
     }
     
                 failureBlock: ^(NSError *err) {}
     ];
}

#define SIXTY_PERCENT_REDUCTION 0.6

/// \brief add photo / image metadata to image file
///
/// This routine will add in the photo meta data (tiff, exif, gps) to the file passed.
/// This is done since the file is stripped of it's data for resizing, etc.
///
/// \param[in] dictionaryOfMetaData, this is the root dictionary that contains the metadata to be added
/// \param[in] stringImageFullFilePath, this is the full path for the image to add the metadata to
///
/// \return, bool, true if all is ok
///
- (BOOL) addMetadata: (NSDictionary *) dictionaryOfMetaData toImageFullFilePath: (NSString *) stringImageFullFilePath {
    BOOL operationSuccessful = YES;
    
    if (dictionaryOfMetaData) {
        NSData *dataFromImage = [[NSData alloc] initWithContentsOfFile: stringImageFullFilePath];
        
        NSMutableDictionary *dictionaryOfTIFFMetaData = [dictionaryOfMetaData objectForKey: @"{TIFF}"];
        NSMutableDictionary *dictionaryOfGPSMetaData = [dictionaryOfMetaData objectForKey: @"{GPS}"];
        NSMutableDictionary *dictionaryOfEXIFMetaData = [dictionaryOfMetaData objectForKey: @"{Exif}"];
        
        if (!dictionaryOfTIFFMetaData) {
            dictionaryOfTIFFMetaData = [[NSMutableDictionary alloc] init];
        }
        
        if (!dictionaryOfEXIFMetaData) {
            dictionaryOfEXIFMetaData = [[NSMutableDictionary alloc] init];
        }
        
        if (!dictionaryOfGPSMetaData) {
            dictionaryOfGPSMetaData = [[NSMutableDictionary alloc] init];
        }
        
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef) dataFromImage, NULL);
        
        NSDictionary *metadata = (__bridge NSDictionary *) CGImageSourceCopyPropertiesAtIndex(source, 0, NULL);
        NSMutableDictionary *metadataAsMutable = [metadata mutableCopy];
        
        [metadataAsMutable setObject: dictionaryOfEXIFMetaData forKey: (NSString *) kCGImagePropertyExifDictionary];
        [metadataAsMutable setObject: dictionaryOfGPSMetaData forKey: (NSString *) kCGImagePropertyGPSDictionary];
        [metadataAsMutable setObject: dictionaryOfTIFFMetaData forKey: (NSString *) kCGImagePropertyTIFFDictionary];
        
        CFStringRef UTI = CGImageSourceGetType(source);
        NSMutableData *dest_data = [[NSMutableData alloc] init];
        CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef) dest_data, UTI, 1, NULL);
        
        if (!destination) {
            operationSuccessful = NO;
        }
        
        CGImageDestinationAddImageFromSource(destination, source, 0, (__bridge CFDictionaryRef) metadataAsMutable);
        
        BOOL success = CGImageDestinationFinalize(destination);
        
        if (!success) {
            operationSuccessful = NO;
        }
        
        NSError *error;
        [dest_data writeToFile: stringImageFullFilePath options: NSDataWritingFileProtectionNone error: &error];
        
        if (error) {
            operationSuccessful = NO;
        }
        
        CFRelease(destination);
        CFRelease(source);
    }
    
    return operationSuccessful;
}

/// \brief reduce the image and add to list
///
/// This routine will reduce the image size for transfer and add it to the photo list
///
/// \param[in] theImage, the image to be added
/// \param[in] stringImageFullFilePath, the full file path for the image to be saved
/// \param[in] dictionaryOfMetaData, the metadata to be added to the image
///
- (void) useImageWithReduction: (UIImage *) theImage destFullPath: (NSString *) stringImageFullFilePath metaData: dictionaryOfMetaData {
    
    NSData *pngData = UIImageJPEGRepresentation(theImage, SIXTY_PERCENT_REDUCTION);
    
    BOOL operationOK = NO;
    
    if (stringImageFullFilePath != nil) {
        // can do other stuff here, add to photo list, etc.
        operationOK = YES;
        [pngData writeToFile: stringImageFullFilePath atomically: YES];
        operationOK = [self addMetadata: dictionaryOfMetaData toImageFullFilePath: stringImageFullFilePath];
    }
    
    if (!operationOK) {
        // error condition here
    }
}

/// \brief return the meta data root dictionary for an image file
///
/// This routine will return the proper dictionary that has the image's meta data.
///
/// \param[in] stringImageFullFilePath, the full file path for the image
///
/// \return NSDictionary, the dictionary that has the metadata entries like "{EXIF}"
///
- (NSDictionary *) getMetaDataFromImageFullFilePath: (NSString *) stringImageFullFilePath {
    NSData *dataFromImage = [[NSData alloc] initWithContentsOfFile: stringImageFullFilePath];
    CIImage *ciImageFromData = [CIImage imageWithData: dataFromImage];
    NSDictionary *dictionaryOfMetaData = [ciImageFromData properties];
    return dictionaryOfMetaData;
}

/// \brief called when the image copy is done
///
/// Once the image copy is done using the assets copy (and camera input), this routine will continue with the photo processing.
///
/// \param[in] stringImageFullFilePath, the full file spec for the image.
///
- (void) continueAfterImageFileCopy: (NSString *) stringImageFullFilePath {
    NSDictionary *dictionaryOfMetaData = [self getMetaDataFromImageFullFilePath: stringImageFullFilePath];
    UIImage *image = [UIImage imageWithContentsOfFile: stringImageFullFilePath];
    UIImage *imageSmaller = [self resizeImage: image];
    [self useImageWithReduction: imageSmaller destFullPath: stringImageFullFilePath metaData: dictionaryOfMetaData];
}

- (UIImage *) resizeImage: (UIImage*) image {
    // resize image as needed here
    return image;
}


@end
