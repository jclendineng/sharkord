import { describe, expect, test } from 'bun:test';
import { clampCropOffset, CROP_SIDE, getCropDrawRect } from '../helpers';

const WIDE = { width: 1200, height: 600 };

describe('icon crop', () => {
  test('should never let the square show past the edge of the picture', () => {
    // at zoom one the short side fills the square, so only the long side has room to move
    expect(clampCropOffset({ x: 9999, y: 9999 }, WIDE, 1)).toEqual({
      x: CROP_SIDE / 2,
      y: 0
    });
  });

  test('should allow more movement when zoomed in', () => {
    const { y } = clampCropOffset({ x: 0, y: -9999 }, WIDE, 2);

    expect(y).toBe(-CROP_SIDE / 2);
  });

  test('should land the centre of the picture in the centre of the output', () => {
    const rect = getCropDrawRect(WIDE, 1, { x: 0, y: 0 }, 512);

    expect(rect.height).toBe(512);
    expect(rect.x + rect.width / 2).toBe(256);
  });

  test('should scale a drag from the screen up to the output', () => {
    const moved = getCropDrawRect(WIDE, 1, { x: 30, y: 0 }, 600);
    const centred = getCropDrawRect(WIDE, 1, { x: 0, y: 0 }, 600);

    expect(moved.x - centred.x).toBe(60);
  });
});
