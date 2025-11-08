# Year at a Glance - Feature Plan

## Overview
Create a controlled React component that shows rowing progress day-by-day for 2025, allowing users to step through each day of the year and see feedback as if they're experiencing the journey one day at a time. This will provide an engaging "replay" of their rowing year.

**Scope**: 2025 only (all data is from 2025, no historical years)

## Goals
- Reuse existing components with minimal modifications
- Create an interactive, controlled playback experience
- Show cumulative progress and daily feedback
- Make the year's journey feel rewarding and motivating

## Current Architecture Analysis

### Existing Components to Reuse

1. **ActivityMap** (`src/components/ActivityMap.tsx`)
   - Currently processes `rowsData` and displays 52 weeks
   - Uses `processActivityData()` to convert timestamps to date counts
   - Applies date filtering (currently filters to 2025+)
   - **Reuse Strategy**: Accept optional `currentDate` prop to limit data shown

2. **ActivityGrid** (`src/components/ActivityGrid.tsx`)
   - Renders weeks and day cells
   - Handles month labels and untracked week highlighting
   - **Reuse Strategy**: Already receives filtered activity data, no changes needed

3. **Week** (`src/components/Week.tsx`)
   - Displays individual week columns with totals
   - Shows untracked count for first untracked week
   - **Reuse Strategy**: Works with filtered data, totals update automatically as playback progresses (no changes needed)

4. **DayCell** (`src/components/DayCell.tsx`)
   - Shows individual day with activity count
   - Color-codes based on activity level (0-6+)
   - Has future date detection
   - **Reuse Strategy**: No changes needed - visual updating of map filling in is sufficient feedback

### Data Flow
```
rows.txt → rowsData (string[]) → processActivityData() → activity map → filtered by date → components
```

## Implementation Plan

### 1. Create New Page Route
**File**: `src/app/at-a-glance/page.tsx`
- Read `rows.txt` file
- Render the new `YearAtAGlance` component
- Pass rowsData to component

### 2. Create Main Controller Component
**File**: `src/components/YearAtAGlance.tsx`

**State Management**:
```typescript
const [currentDayIndex, setCurrentDayIndex] = useState(0); // Which day we're "on"
const [isPlaying, setIsPlaying] = useState(false); // Auto-advance mode
const [playbackSpeed, setPlaybackSpeed] = useState(1000); // ms per day
```

**Computed Values**:
- `currentDate`: The date string we're viewing (based on index)
- `filteredRowsData`: Only timestamps up to and including currentDate
- `daysArray`: All calendar days in 2025 (Jan 1 - Dec 31, 365 days)
- `totalDays`: 365 (all days in 2025)
- `completionPercentage`: currentDayIndex / 365

**Key Features**:
- Timeline slider to scrub through days
- Play/Pause button for auto-advance
- Speed controls (1x, 2x, 5x, 10x)
- "Today's" stats display (for the current day in playback)
- Cumulative stats display

### 3. Extend Existing Components (Minimal Changes)

#### ActivityMap Enhancement
**File**: `src/components/ActivityMap.tsx`

Add optional prop:
```typescript
interface ActivityMapProps {
  rowsData: string[];
  currentDate?: string; // If provided, only show data up to this date
}
```

**Implementation**:
- When `currentDate` is provided, filter `rowsData` before processing
- Otherwise behaves exactly as before (backwards compatible)
- No changes needed to child components (DayCell, Week, ActivityGrid)

### 4. Create Helper Functions
**File**: `src/lib/atAGlanceHelpers.ts`

```typescript
// Generate all calendar dates for 2025 (Jan 1 - Dec 31)
export function generateCalendarDays2025(): string[] // Returns array of 365 YYYY-MM-DD strings

// Filter rows data to only include timestamps up to a given date
export function filterRowsUpToDate(rowsData: string[], currentDate: string): string[]

// Get stats for a specific date (row count that day)
export function getStatsForDate(rowsData: string[], date: string): DayStats

// Get cumulative stats up to a date (total rows, current streak, longest streak)
export function getCumulativeStats(rowsData: string[], currentDate: string): CumulativeStats

// Calculate streak statistics
export function calculateStreaks(rowsData: string[], upToDate: string): {
  currentStreak: number;      // Consecutive days with activity ending at upToDate
  longestStreak: number;       // Longest consecutive streak in the period
  totalRowsStreak: number;     // Total cumulative rows
}
```

### 5. UI Components Needed

#### Timeline Controls
**File**: `src/components/TimelineControls.tsx`
- Range slider (day 1 to day 365)
- Current date display (e.g., "May 25, 2025")
- Play/Pause button
- Speed selector (1x, 2x, 5x, 10x)
- Skip buttons (previous day, next day, first day, last day)

#### Stats Display
**File**: `src/components/PlaybackStats.tsx`
- Current day's activity count
- Cumulative totals (total rows up to current date)
- Streak information:
  - **Current Streak**: Consecutive days with rowing activity (ends at current playback date)
  - **Longest Streak**: Longest consecutive day streak up to current playback date
  - **Total Rows**: Cumulative row count
- Progress percentage (day N of 365)

### 6. Layout Design

```
┌─────────────────────────────────────────────────┐
│              Year at a Glance                    │
├─────────────────────────────────────────────────┤
│  [Current Date Display]     Day 145 of 365      │
│  Progress: ▓▓▓▓▓▓▓░░░░░░░░░░ 39.7%             │
├─────────────────────────────────────────────────┤
│                                                  │
│          [Activity Map Component]                │
│         (showing data up to current date)        │
│                                                  │
├─────────────────────────────────────────────────┤
│  Today's Activity: 3 rows                        │
│  Total Rows So Far: 145                          │
│  Current Streak: 5 days                          │
│  Longest Streak: 12 days                         │
├─────────────────────────────────────────────────┤
│  Timeline Controls:                              │
│  [◄◄] [◄] [▶] [▶▶]  Speed: [1x ▾]              │
│  ├──●────────────────────────────────┤          │
│                                                  │
└─────────────────────────────────────────────────┘
(Timeline spans all 365 days of 2025)
```

## Data Processing Strategy

### Option A: Filter Timestamps (Recommended)
- Keep rows.txt data as-is
- Filter the timestamp array to only include dates ≤ currentDate
- Pass filtered array to existing `processActivityData()`
- **Pros**: Simple, reuses all existing logic
- **Cons**: Re-processes data on each date change (acceptable with memoization)

### Option B: Pre-process All Days
- Build a full chronological map of all dates upfront
- Slice the map at currentDate
- **Pros**: Potentially faster for scrubbing
- **Cons**: More complex, harder to maintain

**Decision**: Use Option A with React.useMemo() for performance

## Edge Cases to Handle

1. **Empty days**: Days with no rowing activity (show as 0 count)
2. **Multiple rows per day**: Already handled by existing components
3. **First day**: Show appropriate "journey begins" messaging
4. **Last day**: Show completion celebration
5. **Untracked rows (???)**:
   - Roughly one ??? per day during initial tracking period
   - Won't count towards total row count in stats
   - Will appear in ActivityMap visualization (existing logic handles display)
   - Timeline playback starts from first tracked date (skips ??? rows)
   - Stats display: Show tracked vs untracked count separately
6. **Playback at end**: Pause briefly (2-3 seconds) on Dec 31, then loop back to Jan 1
7. **Date gaps**: Calendar includes all 365 days, even with no activity

## Performance Considerations

1. **Memoization**: Use `useMemo()` for expensive computations
   - Date filtering
   - Stats calculations
   - Days array generation

2. **Throttling**: Limit playback speed to avoid overwhelming React
   - Use `useEffect()` with interval cleanup
   - Consider `requestAnimationFrame()` for smooth scrubbing

3. **Component Optimization**: Existing components already optimized
   - ActivityGrid renders only visible weeks
   - DayCell is lightweight

## Future Enhancements (Out of Scope)

- Export year replay as video/GIF
- Share progress snapshots
- Compare year-over-year progress
- Milestone celebrations (every 50 rows, etc.)
- Annotations/notes on specific dates
- Monthly/quarterly summaries

## Files to Create

1. `src/app/at-a-glance/page.tsx` - Route page
2. `src/components/YearAtAGlance.tsx` - Main controller component
3. `src/components/TimelineControls.tsx` - Playback controls
4. `src/components/PlaybackStats.tsx` - Stats display
5. `src/lib/atAGlanceHelpers.ts` - Helper functions
6. `src/types/atAGlance.ts` - Type definitions

## Files to Modify

1. `src/components/ActivityMap.tsx` - Add optional currentDate prop

## Testing Considerations

1. **Unit Tests**:
   - Helper functions (date filtering, stats calculations)
   - Component prop handling

2. **Integration Tests**:
   - Playback controls affect displayed data correctly
   - Date scrubbing updates all dependent components

3. **Manual Testing**:
   - Smooth playback at various speeds
   - Accurate stats at random dates
   - Proper handling of first/last days

## Implementation Order

1. Create helper functions and types
2. Extend ActivityMap with currentDate prop
3. Create TimelineControls component
4. Create PlaybackStats component
5. Create main YearAtAGlance component
6. Create page route
7. Test and refine
8. Add polish (animations, messages)

## Design Decisions (Finalized)

### Initial State
- Playback starts at **Jan 1, 2025** (first calendar day)
- Timeline position: Day 1 of 365
- Map shows empty state (or first day's data if available)

### Visual Feedback
- **Future dates**: Shown as empty blank cells (not yet reached in playback)
- **Past dates**: Full color based on activity level (map "fills in" as playback progresses)
- **Current playback day**: No special highlighting needed - the progressive filling provides sufficient visual feedback

### Playback Controls
- **Speeds**: 1x (1 second/day), 2x, 5x, 10x
- **End behavior**: Pause briefly on Dec 31 (2-3 seconds), then automatically loop back to Jan 1 and resume playing
- **Progress display**: "Day X of 365" (calendar day number)

### Stats Display
- **Total Rows**: Only tracked rows (excludes ???)
- **Untracked Count**: Shown separately (e.g., "+ 15 untracked")
- **Streaks**: Based on consecutive calendar days with activity
- **Current Streak**: Must end on current playback date
- **Longest Streak**: Calculated up to current playback date only

## Success Criteria

- ✅ User can scrub through entire year smoothly (365 days)
- ✅ Activity map updates correctly to show only past data
- ✅ Stats accurately reflect data up to current playback date
- ✅ Playback speed controls work as expected (1x, 2x, 5x, 10x)
- ✅ Existing components remain backwards compatible
- ✅ Performance is smooth even with full year of data
- ✅ UI is intuitive and engaging
- ✅ Untracked rows (???) are handled gracefully
