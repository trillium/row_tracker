import { getYearDays } from "../lib/activityMapHelpers";
import { parseISO } from "date-fns";

describe("getYearDays", () => {
    it("should return an array of strings for a given year", () => {
        const result = getYearDays(2025);
        expect(Array.isArray(result)).toBe(true);
        expect(result.length).toBeGreaterThan(0);
        result.forEach(day => {
            expect(typeof day).toBe("string");
            expect(day).toMatch(/^\d{4}-\d{2}-\d{2}$/);
        });
    });

    it("should include the first day of the year", () => {
        const result = getYearDays(2025);
        expect(result).toContain("2025-01-01");
    });

    it("should have length that is a multiple of 7 (complete weeks)", () => {
        const result = getYearDays(2025);
        expect(result.length % 7).toBe(0);
    });

    it("should start with a Sunday", () => {
        const result = getYearDays(2025);
        const firstDay = parseISO(result[0]);
        expect(firstDay.getDay()).toBe(0); // 0 = Sunday
    });

    it("should end with a Saturday", () => {
        const result = getYearDays(2025);
        const lastDay = parseISO(result[result.length - 1]);
        expect(lastDay.getDay()).toBe(6); // 6 = Saturday
    });

    it("should cover the entire year plus partial weeks", () => {
        const result = getYearDays(2025);
        // For 2025, should include days from late 2024 to early 2026
        const has2024 = result.some(day => day.startsWith("2024"));
        const has2025 = result.some(day => day.startsWith("2025"));
        const has2026 = result.some(day => day.startsWith("2026"));
        expect(has2024).toBe(true);
        expect(has2025).toBe(true);
        expect(has2026).toBe(true);
    });

    it("should return consistent results for the same year", () => {
        const result1 = getYearDays(2025);
        const result2 = getYearDays(2025);
        expect(result1).toEqual(result2);
    });
});