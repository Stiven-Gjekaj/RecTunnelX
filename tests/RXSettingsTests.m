#import "RXTest.h"
#import "RXSettings.h"

static NSString *TemporaryPath(void) {
    return [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"rxsettings-%@.plist", [[NSProcessInfo processInfo] globallyUniqueString]]];
}

RX_TEST(test_settings_defaults_when_file_is_missing) {
    RXSettings *settings = [RXSettings settingsWithContentsOfFile:TemporaryPath()];
    RX_EXPECT(settings.enabled);
    RX_EQUAL_INT(settings.framesPerSecond, 30);
    RX_EQUAL_INT(settings.bitsPerSecond, 3000000);
    RX_EQUAL_INT(settings.scale, 1);
}

RX_TEST(test_settings_write_and_read_back) {
    NSString *path = TemporaryPath();
    RXSettings *settings = [RXSettings new];
    settings.enabled = NO;
    settings.framesPerSecond = 24;
    settings.bitsPerSecond = 1500000;
    settings.scale = 2;
    RX_EXPECT([settings writeToFile:path]);
    RXSettings *read = [RXSettings settingsWithContentsOfFile:path];
    RX_EQUAL(read.dictionary, settings.dictionary);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

RX_TEST(test_settings_file_values_are_clamped) {
    NSString *path = TemporaryPath();
    [@{ @"fps": @500, @"bitrate": @1, @"scale": @9, @"enabled": @"text" } writeToFile:path atomically:YES];
    RXSettings *settings = [RXSettings settingsWithContentsOfFile:path];
    RX_EQUAL_INT(settings.framesPerSecond, 60);
    RX_EQUAL_INT(settings.bitsPerSecond, 250000);
    RX_EQUAL_INT(settings.scale, 2);
    RX_EXPECT(settings.enabled);
    [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

RX_TEST(test_settings_apply_query) {
    RXSettings *settings = [RXSettings new];
    NSString *error = nil;
    RX_EXPECT(([settings applyQuery:@{ @"enabled": @"no", @"fps": @"25", @"bitrate": @"99999999999" } error:&error]));
    RX_EXPECT(!settings.enabled);
    RX_EQUAL_INT(settings.framesPerSecond, 25);
    RX_EQUAL_INT(settings.bitsPerSecond, 10000000);
}

RX_TEST(test_settings_bad_query_changes_nothing) {
    RXSettings *settings = [RXSettings new];
    NSDictionary *before = settings.dictionary;
    NSString *error = nil;
    RX_EXPECT((![settings applyQuery:@{ @"fps": @"20", @"bitrate": @"fast" } error:&error]));
    RX_EQUAL(error, @"bitrate is not a number");
    RX_EXPECT((![settings applyQuery:@{ @"color": @"red" } error:&error]));
    RX_EQUAL(error, @"color is not a setting");
    RX_EXPECT((![settings applyQuery:@{ @"audio": @"maybe" } error:&error]));
    RX_EQUAL(settings.dictionary, before);
}
