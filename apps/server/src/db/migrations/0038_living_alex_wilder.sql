CREATE TABLE `sessions` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` integer NOT NULL,
	`os` text,
	`device` text,
	`user_agent` text,
	`ip` text,
	`city` text,
	`region` text,
	`country` text,
	`created_at` integer NOT NULL,
	`last_active_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `sessions_user_active_idx` ON `sessions` (`user_id`,`last_active_at`);--> statement-breakpoint
ALTER TABLE `push_devices` ADD `session_id` text REFERENCES sessions(id) ON DELETE cascade;