import { ImageResponse } from "next/og";
import { countLines } from "../lib/countLines";
import {
  getTimezone,
  getCurrentDateInTimezone,
  getDaysPassedThisYear,
} from "../lib/dateHelpers";

// Tailwind classes from RowingStats
const textClassesBase =
  "text-4xl font-bold inline-block text-transparent bg-clip-text";
const textClassesPositive = "from-black via-green-500 to-green-400";
const textClassesNegative = "from-black via-red-500 to-red-400";
const textClassesGradientDirection = "bg-gradient-to-b";

// Image metadata
export const alt = "Trillium's Rowing Tracker";
export const size = {
  width: 1200,
  height: 630,
};

export const contentType = "image/png";

// Image generation
export default async function Image() {
  const timezone = await getTimezone();
  const today = await getCurrentDateInTimezone(timezone);
  const rows = await countLines();
  const daysPassedThisYear = getDaysPassedThisYear(today);
  const rowBoolean = daysPassedThisYear - rows <= 0;

  let statusDiv;
  if (daysPassedThisYear - rows <= 0) {
    statusDiv = (
      <div
        className={`${textClassesBase} ${textClassesPositive} ${textClassesGradientDirection}`}
        style={{ marginBottom: 24 }}
      >
        {`Rows ahead: +${Math.abs(daysPassedThisYear - rows)}`}
      </div>
    );
  } else {
    statusDiv = (
      <div
        className={`${textClassesBase} ${textClassesNegative} ${textClassesGradientDirection}`}
        style={{ marginBottom: 24 }}
      >
        {`Rows behind: -${daysPassedThisYear - rows}`}
      </div>
    );
  }

  return new ImageResponse(
    (
      <div
        style={{
          fontSize: 64,
          background: "black",
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          alignItems: "flex-start",
          justifyContent: "center",
          padding: 64,
          margin: 32,
          border: `8px solid ${rowBoolean ? "#22c55e" : "#ef4444"}`,
          boxSizing: "border-box",
        }}
      >
        <div
          style={{ fontWeight: 700, marginBottom: 24, color: "white" }}
        >{`Days passed this year: ${daysPassedThisYear}`}</div>
        <div
          style={{ fontWeight: 700, marginBottom: 24, color: "white" }}
        >{`Rows this year: ${rows}`}</div>
        {statusDiv}
      </div>
    ),
    {
      ...size,
    }
  );
}
