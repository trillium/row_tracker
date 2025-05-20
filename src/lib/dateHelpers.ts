import fs from "fs/promises";

// Evaluate 'now' at module load time (build time for SSG)
const buildTimeNow = new Date();

export async function getTimezone(): Promise<string> {
    const timezone = await fs.readFile(process.cwd() + "/timezone.txt", "utf-8");
    return timezone.trim();
}

export async function getCurrentDateInTimezone(timezone: string): Promise<Date> {
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
    const parts = formatter.formatToParts(buildTimeNow);
    const getPart = (type: string) => parts.find((p) => p.type === type)?.value || "0";
    return new Date(
        `${getPart("year")}-${getPart("month")}-${getPart("day")}` +
        `T${getPart("hour")}:${getPart("minute")}:${getPart("second")}`
    );
}

export function getDaysDifference(date1: Date, date2: Date): number {
    const timeDifference = date1.getTime() - date2.getTime();
    return Math.ceil(timeDifference / (1000 * 3600 * 24));
}

export function getDaysPassedThisYear(today: Date): number {
    const currentYear = today.getFullYear();
    const startOfYear = new Date(currentYear, 0, 1);
    return getDaysDifference(today, startOfYear);
}
