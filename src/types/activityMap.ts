export interface ActivityMapProps {
    rowsData: string[];
}

export interface ActivityByDate {
    [date: string]: number;
}

export interface ProcessedActivityData {
    activity: ActivityByDate;
    firstDate: string | null;
    untracked: {
        count: number;
        date: string | null;
    };
}