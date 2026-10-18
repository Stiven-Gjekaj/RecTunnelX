// Reads an AVC decoder configuration record ("avcC").
// The H.264 encoder gives this record in the format description of its
// output. The record holds the SPS units, the PPS units, and the size of
// the length field before each NAL unit.

#import <Foundation/Foundation.h>

@interface RXAVCConfig : NSObject
@property (nonatomic, readonly) NSArray *sps;  // NSData, one for each SPS unit
@property (nonatomic, readonly) NSArray *pps;  // NSData, one for each PPS unit
@property (nonatomic, readonly) int nalLengthSize;  // 1, 2, or 4
// Returns nil if the record is not complete or is not version 1.
+ (instancetype)configWithRecord:(NSData *)record;
@end
