import { describe, expect, test } from 'bun:test';
import { extractUrls } from '../extract-urls';

describe('extractUrls', () => {
  test('should give a bare domain https', () => {
    expect(extractUrls('see chat.example.com today')).toEqual([
      'https://chat.example.com'
    ]);
  });

  test('should keep the scheme a link was written with', () => {
    expect(
      extractUrls('http://old.example.com and https://new.example.com')
    ).toEqual(['http://old.example.com', 'https://new.example.com']);
  });

  test('should list a link once', () => {
    expect(extractUrls('https://example.com then https://example.com')).toEqual(
      ['https://example.com']
    );
  });
});
