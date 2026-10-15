CREATE TABLE `login_requests` (
	`id` text PRIMARY KEY NOT NULL,
	`secret_hash` text NOT NULL,
	`poll_key_hash` text NOT NULL,
	`user_id` integer,
	`status` text NOT NULL,
	`request_os` text,
	`request_device` text,
	`request_ip` text,
	`created_at` integer NOT NULL,
	`expires_at` integer NOT NULL,
	FOREIGN KEY (`user_id`) REFERENCES `users`(`id`) ON UPDATE no action ON DELETE cascade
);
--> statement-breakpoint
CREATE INDEX `login_requests_expires_idx` ON `login_requests` (`expires_at`);