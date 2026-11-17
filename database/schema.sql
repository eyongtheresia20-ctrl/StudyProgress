-- StudyProgress Cameroon Edition MySQL Schema (Import via phpMyAdmin)
-- Compatible with MySQL 5.7+, MySQL 8.0+, and MariaDB 10.4+

CREATE DATABASE IF NOT EXISTS `study_progress_db`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE `study_progress_db`;

CREATE TABLE IF NOT EXISTS `users` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `full_name` VARCHAR(140) NOT NULL,
  `email` VARCHAR(190) NOT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `role` ENUM('student', 'admin') NOT NULL DEFAULT 'student',
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_users_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `subsystems` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `code` VARCHAR(16) NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `description` VARCHAR(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_subsystems_code` (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `classes` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `subsystem_id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(80) NOT NULL,
  `level_order` SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  PRIMARY KEY (`id`),
  KEY `idx_classes_subsystem` (`subsystem_id`),
  CONSTRAINT `fk_classes_subsystem`
    FOREIGN KEY (`subsystem_id`) REFERENCES `subsystems` (`id`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `student_profiles` (
  `user_id` INT UNSIGNED NOT NULL,
  `subsystem_id` INT UNSIGNED DEFAULT NULL,
  `class_id` INT UNSIGNED DEFAULT NULL,
  `age` TINYINT UNSIGNED DEFAULT NULL,
  `questionnaire_completed` TINYINT(1) NOT NULL DEFAULT 0,
  `favourite_subject` VARCHAR(100) DEFAULT NULL,
  `difficult_subjects_json` TEXT DEFAULT NULL,
  `difficulty_reason` VARCHAR(160) DEFAULT NULL,
  `hobbies_json` TEXT DEFAULT NULL,
  `activity_style` VARCHAR(40) NOT NULL DEFAULT 'both',
  `learning_style` VARCHAR(60) NOT NULL DEFAULT 'practical_examples',
  `fallback_preference` VARCHAR(80) NOT NULL DEFAULT 'another_example',
  `exercise_preference` VARCHAR(60) NOT NULL DEFAULT 'short_quizzes',
  `preferred_study_period` VARCHAR(40) NOT NULL DEFAULT 'evening',
  `academic_goal` VARCHAR(255) DEFAULT NULL,
  `daily_goal_minutes` INT UNSIGNED NOT NULL DEFAULT 60,
  `reminder_hour` TINYINT UNSIGNED NOT NULL DEFAULT 18,
  `reminder_minute` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`user_id`),
  CONSTRAINT `fk_profiles_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
    ON DELETE CASCADE,
  CONSTRAINT `fk_profiles_subsystem`
    FOREIGN KEY (`subsystem_id`) REFERENCES `subsystems` (`id`)
    ON DELETE SET NULL,
  CONSTRAINT `fk_profiles_class`
    FOREIGN KEY (`class_id`) REFERENCES `classes` (`id`)
    ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `program_topics` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `subsystem_id` INT UNSIGNED NOT NULL,
  `class_id` INT UNSIGNED NOT NULL,
  `subject_name` VARCHAR(100) NOT NULL,
  `topic_title` VARCHAR(200) NOT NULL,
  `subtopics` TEXT DEFAULT NULL,
  `created_by` INT UNSIGNED DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_pt_sub_class` (`subsystem_id`, `class_id`),
  CONSTRAINT `fk_pt_subsystem`
    FOREIGN KEY (`subsystem_id`) REFERENCES `subsystems` (`id`)
    ON DELETE CASCADE,
  CONSTRAINT `fk_pt_class`
    FOREIGN KEY (`class_id`) REFERENCES `classes` (`id`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `official_progressions` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `subsystem_id` INT UNSIGNED NOT NULL,
  `class_id` INT UNSIGNED NOT NULL,
  `subject_name` VARCHAR(100) NOT NULL,
  `topic_title` VARCHAR(200) NOT NULL,
  `subtopics` TEXT DEFAULT NULL,
  `week_number` SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  `start_date` DATE NOT NULL,
  `end_date` DATE NOT NULL,
  `study_days` VARCHAR(60) DEFAULT NULL,
  `created_by` INT UNSIGNED DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_prog_class_dates` (`subsystem_id`, `class_id`, `start_date`, `end_date`),
  CONSTRAINT `fk_prog_subsystem`
    FOREIGN KEY (`subsystem_id`) REFERENCES `subsystems` (`id`)
    ON DELETE CASCADE,
  CONSTRAINT `fk_prog_class`
    FOREIGN KEY (`class_id`) REFERENCES `classes` (`id`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `student_topic_progress` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` INT UNSIGNED NOT NULL,
  `progression_id` INT UNSIGNED NOT NULL,
  `status` ENUM('not_started', 'in_progress', 'needs_revision', 'understood') NOT NULL DEFAULT 'not_started',
  `understanding_level` ENUM('none', 'partial', 'full') NOT NULL DEFAULT 'none',
  `quiz_score` TINYINT UNSIGNED DEFAULT NULL,
  `weakness_notes` TEXT DEFAULT NULL,
  `last_studied_at` DATETIME DEFAULT NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_user_progression` (`user_id`, `progression_id`),
  CONSTRAINT `fk_stp_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
    ON DELETE CASCADE,
  CONSTRAINT `fk_stp_progression`
    FOREIGN KEY (`progression_id`) REFERENCES `official_progressions` (`id`)
    ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `ai_interactions` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` INT UNSIGNED NOT NULL,
  `progression_id` INT UNSIGNED DEFAULT NULL,
  `interaction_type` ENUM('chat', 'quiz', 'summary', 'simulation', 'check') NOT NULL DEFAULT 'chat',
  `prompt` TEXT NOT NULL,
  `response` MEDIUMTEXT NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_ai_user` (`user_id`),
  CONSTRAINT `fk_ai_user`
    FOREIGN KEY (`user_id`) REFERENCES `users` (`id`)
    ON DELETE CASCADE,
  CONSTRAINT `fk_ai_progression`
    FOREIGN KEY (`progression_id`) REFERENCES `official_progressions` (`id`)
    ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
