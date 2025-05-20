import {
  getTimezone,
  getCurrentDateInTimezone,
  getDaysPassedThisYear,
} from "../lib/dateHelpers";
import { countLines } from "../lib/countLines";
import clsx from "clsx";
import React from "react";

export async function RowingStats() {
  const timezone = await getTimezone();
  const today = await getCurrentDateInTimezone(timezone);
  const rows = await countLines();
  const daysPassedThisYear = getDaysPassedThisYear(today);
  const rowBoolean = daysPassedThisYear - rows <= 0;

  const textClassesBase =
    "text-4xl font-bold inline-block text-transparent bg-clip-text";
  const textClassesPositive = "from-black via-green-500 to-green-400";
  const textClassesNegative = "from-black via-red-500 to-red-400";
  const textClassesGradientDirection = "bg-gradient-to-b";

  return (
    <div
      className="flex flex-col items-start border rounded-lg p-4"
      style={{ borderColor: rowBoolean ? "#22c55e" : "#ef4444" }}
    >
      <p>{`Days passed this year: ${daysPassedThisYear}`}</p>
      <p>{`Rows this year: ${rows}`}</p>
      {daysPassedThisYear - rows <= 0 && (
        <p
          className={clsx(
            textClassesBase,
            textClassesPositive,
            textClassesGradientDirection
          )}
        >{`Rows ahead: +${Math.abs(daysPassedThisYear - rows)}`}</p>
      )}
      {daysPassedThisYear - rows > 0 && (
        <p
          className={clsx(
            textClassesBase,
            textClassesNegative,
            textClassesGradientDirection
          )}
        >{`Rows behind: -${daysPassedThisYear - rows}`}</p>
      )}
    </div>
  );
}
