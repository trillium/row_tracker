import { ImageResponse } from "next/og";
import { countLines } from "../lib/countLines";
import {
  getTimezone,
  getCurrentDateInTimezone,
  getDaysPassedThisYear,
} from "../lib/dateHelpers";

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
        style={{
          fontSize: 40,
          fontWeight: 700,
          display: "block",
          color: "transparent",
          backgroundImage:
            "linear-gradient(to bottom, black, #22c55e, #4ade80)",
          backgroundClip: "text",
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent",
          marginBottom: 24,
        }}
      >
        {`Rows ahead: +${Math.abs(daysPassedThisYear - rows)}`}
      </div>
    );
  } else {
    statusDiv = (
      <div
        style={{
          fontSize: 40,
          fontWeight: 700,
          display: "block",
          color: "transparent",
          backgroundImage:
            "linear-gradient(to bottom, black, #ef4444, #f87171)",
          backgroundClip: "text",
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent",
          marginBottom: 24,
        }}
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
          borderRadius: 32,
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

{
  /* <div
  style={{
    display: "flex",
    height: "100%",
    width: "100%",
    alignItems: "center",
    justifyContent: "center",
    flexDirection: "column",
    backgroundImage: "linear-gradient(to bottom, #dbf4ff, #fff1f1)",
    fontSize: 60,
    letterSpacing: -2,
    fontWeight: 700,
    textAlign: "center",
  }}
>
  <div
    style={{
      backgroundImage:
        "linear-gradient(90deg, rgb(0, 124, 240), rgb(0, 223, 216))",
      backgroundClip: "text",
      WebkitBackgroundClip: "text",
      color: "transparent",
    }}
  >
    Develop
  </div>
  <div
    style={{
      backgroundImage:
        "linear-gradient(90deg, rgb(121, 40, 202), rgb(255, 0, 128))",
      backgroundClip: "text",
      WebkitBackgroundClip: "text",
      color: "transparent",
    }}
  >
    Preview
  </div>
  <div
    style={{
      backgroundImage:
        "linear-gradient(90deg, rgb(255, 77, 77), rgb(249, 203, 40))",
      backgroundClip: "text",
      WebkitBackgroundClip: "text",
      color: "transparent",
    }}
  >
    Ship
  </div>
</div>; */
}
