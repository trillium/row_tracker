import clsx from "clsx";
import React from "react";

interface DayCellProps {
  dateStr: string;
  count: number;
  isUntracked?: boolean;
}

const DayCell: React.FC<DayCellProps> = ({ dateStr, count, isUntracked = false }) => {
  const isFuture = new Date(dateStr) > new Date();
  const month = new Date(dateStr).getMonth() + 1;
  return (
    <div
      className={clsx("w-4 h-4 p-0.5", {
        "bg-gray-950": isUntracked,
        "bg-black": !isUntracked && month % 2 === 0,
        "bg-teal-950": !isUntracked && month % 2 !== 0,
      })}
    >
      <div
        title={!isFuture ? `${dateStr}: ${count} activities` : undefined} // Tooltip
        className={clsx(
          "w-3 h-3 rounded-sm border flex items-center justify-center",
          {
            "bg-black border-black text-black": isFuture,
            "bg-teal-500 border-white text-teal-600": count === 6 && !isFuture,
            "bg-teal-500 border-teal-100 text-teal-600":
              count === 5 && !isFuture,
            "bg-teal-500 border-teal-400 text-teal-600":
              count === 4 && !isFuture,
            "bg-teal-600 border-slate-800 text-teal-700":
              count === 3 && !isFuture,
            "bg-teal-700 border-slate-800 text-teal-900":
              count === 2 && !isFuture,
            "bg-teal-800 border-slate-800 text-teal-900":
              count === 1 && !isFuture,
            "bg-slate-950 border-slate-800 text-slate-800":
              count === 0 && !isFuture,
          }
        )}
      >
        <span>{count > 0 ? count : ""}</span>
      </div>
    </div>
  );
};

export default DayCell;
