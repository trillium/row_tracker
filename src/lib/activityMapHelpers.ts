import {
    eachDayOfInterval,
    startOfWeek,
    format,
} from "date-fns";
import { ActivityByDate, ProcessedActivityData } from "../types/activityMap";

// Helper to get 52 weeks of days from the week of the given date backwards
/**
 * Generates an array of days for 52 weeks, starting from 51 weeks before the week of the given date to the week of the given date.
 *
 * This function calculates the date range from 51 weeks ago to the current week, ensuring complete weeks are covered.
 * Days are formatted consistently for use as keys in activity maps.
 *
 * @param date - The date from which to start (the current week)
 * @returns An array of strings, each representing a day in "YYYY-MM-DD" format
 *
 * @example
 * const days = getYearDays(new Date());
 * // days: ["2024-10-07", "2024-10-08", ..., "2025-09-30"]
 */
export function getYearDays(date: Date) {
    const currentWeekStart = startOfWeek(date, { weekStartsOn: 0 });
    // Start is 51 weeks before currentWeekStart
    const start = new Date(currentWeekStart);
    start.setDate(start.getDate() - 51 * 7);
    // End is currentWeekStart + 6 days
    const end = new Date(currentWeekStart);
    end.setDate(end.getDate() + 6);
    const days = eachDayOfInterval({ start, end });
    return days.map(day => format(day, "yyyy-MM-dd"));
}

// Process rows data into activity by date
/**
 * Processes an array of timestamp strings into a date-based activity count map and finds the first tracked date.
 *
 * This function takes rowing session timestamps from the data file, validates each
 * timestamp, and aggregates the sessions by date. Multiple sessions on the same
 * date are counted together. It also identifies the earliest valid date.
 *
 * @param rowsData - Array of strings, each representing a rowing session timestamp
 *                   in ISO format (e.g., "2025-03-04T21:47:36-08:00")
 * @returns An object containing the activity map and the first tracked date
 *
 * @example
 * const data = ["2025-01-01T10:00:00Z", "2025-01-01T11:00:00Z", "2025-01-02T10:00:00Z", "invalid"];
 * const result = processActivityData(data);
 * // result: { activity: { "2025-01-01": 2, "2025-01-02": 1 }, firstDate: "2025-01-01", untrackedCount: 1 }
 */
export function processActivityData(rowsData: string[]): ProcessedActivityData {
    const byDate: ActivityByDate = {};
    let earliestDate: Date | null = null;
    let untrackedCount = 0;

    rowsData.forEach((line) => {
        // Process each timestamp line
        if (!line.trim()) {
            return;
        }

        try {
            const parsedDate = new Date(line); // Parse ISO timestamp

            if (isNaN(parsedDate.getTime())) {
                throw new Error("Invalid date");
            }

            const date = format(parsedDate, "yyyy-MM-dd"); // Format to YYYY-MM-DD
            byDate[date] = (byDate[date] || 0) + 1; // Increment count for date

            if (earliestDate === null || parsedDate < earliestDate) {
                earliestDate = parsedDate;
            }
        } catch {
            // Invalid date, count as untracked
            untrackedCount++;
        }
    });

    const firstDate = earliestDate ? format(earliestDate, "yyyy-MM-dd") : null;

    return { activity: byDate, firstDate, untracked: { count: untrackedCount, date: firstDate } };
}

// Get the first tracked date from rows data
/**
 * Finds the earliest date from an array of timestamp strings.
 *
 * This function parses rowing session timestamps and returns the first (earliest)
 * valid date found. Invalid timestamps are skipped.
 *
 * @param rowsData - Array of strings, each representing a rowing session timestamp
 *                   in ISO format (e.g., "2025-03-04T21:47:36-08:00")
 * @returns The earliest valid date as a string in "YYYY-MM-DD" format, or null if no valid dates
 *
 * @example
 * const data = ["2025-01-02T10:00:00Z", "2025-01-01T10:00:00Z"];
 * const firstDate = getFirstTrackedDate(data);
 * // firstDate: "2025-01-01"
 */
export function getFirstTrackedDate(rowsData: string[]): string | null {
    let earliestDate: Date | null = null;

    rowsData.forEach((line) => {
        if (!line.trim()) {
            return;
        }

        try {
            const parsedDate = new Date(line);

            if (isNaN(parsedDate.getTime())) {
                throw new Error("Invalid date");
            }

            if (earliestDate === null || parsedDate < earliestDate) {
                earliestDate = parsedDate;
            }
        } catch {
            // Invalid date, skip
        }
    });

    return earliestDate ? format(earliestDate, "yyyy-MM-dd") : null;
}