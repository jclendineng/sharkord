ALTER TABLE `settings` ADD `afk_channel_id` integer;--> statement-breakpoint
ALTER TABLE `settings` ADD `afk_timeout_seconds` integer DEFAULT 300 NOT NULL;