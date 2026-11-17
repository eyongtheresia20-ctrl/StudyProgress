-- Cameroon Subsystems, Classes & Sample Official Progression
-- Import AFTER schema.sql in phpMyAdmin

USE `study_progress_db`;

INSERT INTO `subsystems` (`id`, `code`, `name`, `description`) VALUES
  (1, 'en', 'English Subsystem', 'Cameroon Anglophone secondary curriculum (Form 1 to Upper Sixth)'),
  (2, 'fr', 'French Subsystem', 'Cameroon Francophone secondary curriculum (6eme to Terminale)')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

INSERT INTO `classes` (`id`, `subsystem_id`, `name`, `level_order`) VALUES
  (1, 1, 'Form 1', 1),
  (2, 1, 'Form 2', 2),
  (3, 1, 'Form 3', 3),
  (4, 1, 'Form 4', 4),
  (5, 1, 'Form 5', 5),
  (6, 1, 'Lower Sixth', 6),
  (7, 1, 'Upper Sixth', 7),
  (8, 2, '6eme', 1),
  (9, 2, '5eme', 2),
  (10, 2, '4eme', 3),
  (11, 2, '3eme', 4),
  (12, 2, 'Seconde', 5),
  (13, 2, 'Premiere', 6),
  (14, 2, 'Terminale', 7)
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

-- Sample official weekly progressions for Form 5 (id=5) and 3eme (id=11)
INSERT INTO `official_progressions`
  (`id`, `subsystem_id`, `class_id`, `subject_name`, `topic_title`, `subtopics`, `week_number`, `start_date`, `end_date`, `study_days`)
VALUES
  (1, 1, 5, 'Mathematics', 'Matrices & Operations', 'Order of matrices, addition, subtraction, scalar and matrix multiplication', 1, DATE_SUB(CURDATE(), INTERVAL 2 DAY), DATE_ADD(CURDATE(), INTERVAL 2 DAY), 'Mon - Wed'),
  (2, 1, 5, 'Physics', 'Linear Motion & Velocity', 'Speed, velocity, acceleration, and distance-time graphs', 1, DATE_ADD(CURDATE(), INTERVAL 1 DAY), DATE_ADD(CURDATE(), INTERVAL 5 DAY), 'Thu - Sat'),
  (3, 1, 5, 'Mathematics', 'Determinants & Inverses', '2x2 determinants, singular matrices, solving linear systems', 2, DATE_ADD(CURDATE(), INTERVAL 6 DAY), DATE_ADD(CURDATE(), INTERVAL 10 DAY), 'Mon - Wed'),
  (4, 1, 5, 'Chemistry', 'Atomic Structure & Bonding', 'Electron shells, ionic and covalent bonding', 2, DATE_ADD(CURDATE(), INTERVAL 9 DAY), DATE_ADD(CURDATE(), INTERVAL 13 DAY), 'Thu - Sat'),
  (5, 2, 11, 'Mathematiques', 'Calcul Litteral & Equations', 'Factorisation, developpement et equations du premier degre', 1, DATE_SUB(CURDATE(), INTERVAL 2 DAY), DATE_ADD(CURDATE(), INTERVAL 3 DAY), 'Lun - Mer'),
  (6, 2, 11, 'Physique', 'Forces et Equilibre', 'Poids, tension, representation vectorielle des forces', 1, DATE_ADD(CURDATE(), INTERVAL 2 DAY), DATE_ADD(CURDATE(), INTERVAL 6 DAY), 'Jeu - Sam')
ON DUPLICATE KEY UPDATE `topic_title` = VALUES(`topic_title`);
