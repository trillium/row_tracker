import { ImageResponse } from "next/og";
import { RowingStats } from "../components/RowingStats";

// Image metadata
export const alt = "Trillium's Rowing Tracker";
export const size = {
  width: 1200,
  height: 630,
};

export const contentType = "image/png";

// Image generation
export default async function Image() {
  return new ImageResponse(
    <RowingStats />,
    // ImageResponse options
    {
      // For convenience, we can re-use the exported opengraph-image
      // size config to also set the ImageResponse's width and height.
      ...size,
    }
  );
}
