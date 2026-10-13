// discord's bounds for a poll, the composer and the server check the same ones
export const POLL_QUESTION_MAX_LENGTH = 300;
export const POLL_ANSWER_MAX_LENGTH = 55;
export const POLL_MIN_ANSWERS = 1;
export const POLL_MAX_ANSWERS = 10;

// how long a poll can run, in hours
export const POLL_DURATIONS_HOURS = [1, 4, 8, 24, 72, 168, 336] as const;
export const POLL_DEFAULT_DURATION_HOURS = 24;
