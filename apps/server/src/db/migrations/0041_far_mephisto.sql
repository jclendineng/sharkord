ALTER TABLE `users` ADD `presence` text DEFAULT 'online' NOT NULL;--> statement-breakpoint
ALTER TABLE `users` ADD `custom_status` text;