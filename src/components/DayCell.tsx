import clsx from "clsx";
import React from "react";

interface DayCellProps {
  dateStr: string;
  count: number;
  isUntracked?: boolean;
}

const DayCell: React.FC<DayCellProps> = ({
  dateStr,
  count,
  isUntracked = false,
}) => {
  // Handle empty cells (padding for calendar alignment)
  if (!dateStr) {
    return (
      <div className="w-4 h-4 p-0.5 bg-transparent">
        <div className="w-3 h-3"></div>
      </div>
    );
  }

  const isFuture = new Date(dateStr) > new Date();
  const month = new Date(dateStr).getMonth() + 1;
  return (
    <div
      className={clsx("w-4 h-4 p-0.5", {
        "bg-gray-200 dark:bg-gray-800": isUntracked,
        "bg-gray-100 dark:bg-gray-900": !isUntracked && month % 2 === 0,
        "bg-teal-50 dark:bg-teal-900": !isUntracked && month % 2 !== 0,
      })}
    >
      <div
        title={!isFuture ? `${dateStr}: ${count} activities` : undefined} // Tooltip
        className={clsx(
          "w-3 h-3 rounded-sm border flex items-center justify-center text-xs font-semibold",
          {
            "bg-gray-100 dark:bg-gray-900 border-gray-300 dark:border-gray-800 text-gray-100 dark:text-gray-900":
              isFuture,
            "bg-teal-100 dark:bg-teal-100 border-teal-400 dark:border-teal-50 shadow-xl shadow-teal-400/60":
              count === 10 && !isFuture,
            "bg-teal-200 dark:bg-teal-200 border-teal-400 dark:border-teal-100 shadow-lg shadow-teal-400/50":
              count === 9 && !isFuture,
            "bg-teal-300 dark:bg-teal-300 border-teal-500 dark:border-teal-100 shadow-md shadow-teal-500/40":
              count === 8 && !isFuture,
            "bg-teal-400 dark:bg-teal-400 border-teal-600 dark:border-teal-200 shadow-sm shadow-teal-500/30":
              count === 7 && !isFuture,
            "bg-teal-500 dark:bg-teal-400 border-teal-700 dark:border-gray-100 text-white dark:text-teal-700":
              count === 6 && !isFuture,
            "bg-teal-500 dark:bg-teal-400 border-teal-600 dark:border-teal-200 text-white dark:text-teal-700":
              count === 5 && !isFuture,
            "bg-teal-500 dark:bg-teal-500 border-teal-500 dark:border-teal-300 text-white dark:text-teal-700":
              count === 4 && !isFuture,
            "bg-teal-600 dark:bg-teal-600 border-teal-400 dark:border-slate-700 text-white dark:text-teal-800":
              count === 3 && !isFuture,
            "bg-teal-700 dark:bg-teal-700 border-teal-300 dark:border-slate-700 text-white dark:text-teal-950":
              count === 2 && !isFuture,
            "bg-teal-800 dark:bg-teal-800 border-teal-200 dark:border-slate-700 text-white dark:text-teal-950":
              count === 1 && !isFuture,
            "bg-gray-200 dark:bg-slate-800 border-gray-400 dark:border-slate-700 text-gray-500 dark:text-slate-700":
              count === 0 && !isFuture,
          }
        )}
      >
        <span
          className={clsx({
            "bg-gradient-to-t from-black via-teal-900 to-teal-100 bg-clip-text text-transparent font-extrabold":
              count === 10 && !isFuture,
            "bg-gradient-to-t from-black via-teal-800 to-teal-200 bg-clip-text text-transparent font-bold":
              count === 9 && !isFuture,
            "bg-gradient-to-t from-black to-teal-300 bg-clip-text text-transparent":
              count === 8 && !isFuture,
            "bg-gradient-to-t from-slate-800 to-teal-400 bg-clip-text text-transparent":
              count === 7 && !isFuture,
          })}
        >
          {count > 0 ? count : ""}
        </span>
      </div>
    </div>
  );
};

export default DayCell;
