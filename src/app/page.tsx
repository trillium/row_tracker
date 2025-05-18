import fs from "fs/promises";
import clsx from "clsx";
import { countLines } from "../lib/countLines";

function getDaysDifference(date1: Date, date2: Date): number {
  const timeDifference = date1.getTime() - date2.getTime();
  return Math.ceil(timeDifference / (1000 * 3600 * 24));
}

function getDaysPassedThisYear(today = new Date()): number {
  const currentYear = today.getFullYear();
  const startOfYear = new Date(currentYear, 0, 1);
  return getDaysDifference(today, startOfYear);
}

const textClassesBase =
  "text-4xl font-bold inline-block text-transparent bg-clip-text";

const textClassesPositive = "from-black via-green-500 to-green-400";

const textClassesNegative = "from-black via-red-500 to-red-400";

const textClassesGradientDirection = "bg-gradient-to-b";

// Read timezone from file
const timezone = (
  await fs.readFile(process.cwd() + "/timezone.txt", "utf-8")
).trim();
// Get current date in the specified timezone
const now = new Date();

// Use Intl.DateTimeFormat to get the date parts in the timezone
// const now = new Date();
const formatter = new Intl.DateTimeFormat("en-US", {
  timeZone: timezone,
  year: "numeric",
  month: "2-digit",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  second: "2-digit",
  hour12: false,
});
const parts = formatter.formatToParts(now);
const getPart = (type: string) =>
  parts.find((p) => p.type === type)?.value || "0";
const today = new Date(
  `${getPart("year")}-${getPart("month")}-${getPart("day")}` +
    `T${getPart("hour")}:${getPart("minute")}:${getPart("second")}`
);

export default async function Home() {
  const rows = await countLines();
  const daysPassedThisYear = getDaysPassedThisYear(today);
  const rowBoolean = daysPassedThisYear - rows <= 0;

  return (
    <div className="flex flex-col gap-8 items-center justify-center max-w-screen">
      <div
        className={clsx("flex flex-col items-start border rounded-lg p-4", {
          "border-green-500": rowBoolean,
          "border-red-500": !rowBoolean,
        })}
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
    </div>
  );
}
