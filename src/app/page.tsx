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

const today = new Date();

export default async function Home() {
  const rows = await countLines();

  const daysPassedThisYear = getDaysPassedThisYear(today);
  const rowBoolean = !!(daysPassedThisYear - rows);

  return (
    <div className="flex flex-col gap-8 items-center justify-center max-w-screen">
      <div
        className={clsx("flex flex-col items-start border rounded-lg p-4", {
          "border-red-500": rowBoolean,
          "border-green-500": !rowBoolean,
        })}
      >
        <p>{`Days passed this year: ${daysPassedThisYear}`}</p>
        <p>{`Rows this year: ${rows}`}</p>
        {daysPassedThisYear - rows <= 0 && (
          <p className="text-green-500 text-2xl">{`Rows ahead: +${
            daysPassedThisYear - rows
          }`}</p>
        )}
        {daysPassedThisYear - rows > 0 && (
          <p className="text-red-500 text-2xl">{`Rows behind: -${
            daysPassedThisYear - rows
          }`}</p>
        )}
      </div>
    </>
  );
}
