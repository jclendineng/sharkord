export const CROP_SIDE = 300;

type TSize = { width: number; height: number };
type TOffset = { x: number; y: number };

// the whole picture covers the square at a zoom of one, its short side across it
export const getCropDisplaySize = (image: TSize, zoom: number): TSize => {
  const fill = (CROP_SIDE / Math.min(image.width, image.height)) * zoom;

  return { width: image.width * fill, height: image.height * fill };
};

// never so far that the square shows past the picture's edge
export const clampCropOffset = (
  offset: TOffset,
  image: TSize,
  zoom: number
): TOffset => {
  const { width, height } = getCropDisplaySize(image, zoom);
  const maxX = (width - CROP_SIDE) / 2;
  const maxY = (height - CROP_SIDE) / 2;

  return {
    x: Math.min(Math.max(offset.x, -maxX), maxX),
    y: Math.min(Math.max(offset.y, -maxY), maxY)
  };
};

// where the picture lands on an output square of this side
export const getCropDrawRect = (
  image: TSize,
  zoom: number,
  offset: TOffset,
  outputSide: number
) => {
  const ratio = outputSide / CROP_SIDE;
  const { width, height } = getCropDisplaySize(image, zoom);

  return {
    x: outputSide / 2 - (width * ratio) / 2 + offset.x * ratio,
    y: outputSide / 2 - (height * ratio) / 2 + offset.y * ratio,
    width: width * ratio,
    height: height * ratio
  };
};
