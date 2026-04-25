

SET SERVEROUTPUT ON;

-- SECTION 0 : CLEANUP  

BEGIN
  FOR t IN (
    SELECT table_name FROM user_tables
    WHERE table_name IN ('WATCH_HISTORY','RATING','PAYMENT',
                         'USER_SUBSCRIPTION','CONTENT_GENRE',
                         'GENRE','CONTENT','SUBSCRIPTION_PLAN','USER_ACCOUNT')
  ) LOOP
    EXECUTE IMMEDIATE 'DROP TABLE '||t.table_name||' CASCADE CONSTRAINTS';
  END LOOP;
END;
/

BEGIN
  FOR s IN (SELECT sequence_name FROM user_sequences
            WHERE sequence_name IN ('USER_SEQ','SUB_SEQ','CONTENT_SEQ',
                                    'GENRE_SEQ','WATCH_SEQ','RATING_SEQ','PAYMENT_SEQ'))
  LOOP
    EXECUTE IMMEDIATE 'DROP SEQUENCE '||s.sequence_name;
  END LOOP;
END;
/

BEGIN
  FOR v IN (SELECT view_name FROM user_views
            WHERE view_name IN ('ACTIVE_SUBSCRIBERS_V','CONTENT_STATS_V'))
  LOOP
    EXECUTE IMMEDIATE 'DROP VIEW '||v.view_name;
  END LOOP;
END;
/


 
-- SECTION 1 : SEQUENCES

CREATE SEQUENCE USER_SEQ    START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE SUB_SEQ     START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE CONTENT_SEQ START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE GENRE_SEQ   START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE WATCH_SEQ   START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE RATING_SEQ  START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;
CREATE SEQUENCE PAYMENT_SEQ START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;


 
-- SECTION 2 : TABLE DEFINITIONS  (9 tables — normalised to 3NF)


-- TABLE 1 : USER_ACCOUNT
--   Stores registered platform users.
CREATE TABLE USER_ACCOUNT (
  user_id    NUMBER         DEFAULT USER_SEQ.NEXTVAL PRIMARY KEY,
  name       VARCHAR2(100)  NOT NULL,
  email      VARCHAR2(150)  UNIQUE NOT NULL,
  phone      VARCHAR2(15),
  password   VARCHAR2(100)  NOT NULL,
  join_date  DATE           DEFAULT SYSDATE,
  status     VARCHAR2(10)   DEFAULT 'ACTIVE'
               CHECK (status IN ('ACTIVE','INACTIVE'))
);

-- TABLE 2 : SUBSCRIPTION_PLAN
--   Master list of available plans (price lives here only — 3NF).
CREATE TABLE SUBSCRIPTION_PLAN (
  plan_id       NUMBER          PRIMARY KEY,
  plan_name     VARCHAR2(50)    NOT NULL,
  price         NUMBER(10,2)    NOT NULL,
  duration_days NUMBER          NOT NULL,
  max_devices   NUMBER          DEFAULT 1,
  resolution    VARCHAR2(10)    CHECK (resolution IN ('480p','720p','1080p','4K')),
  description   VARCHAR2(200)
);

-- TABLE 3 : USER_SUBSCRIPTION
--   Links users to plans. End-date is set by TRIGGER (not manual entry).
CREATE TABLE USER_SUBSCRIPTION (
  sub_id     NUMBER         DEFAULT SUB_SEQ.NEXTVAL PRIMARY KEY,
  user_id    NUMBER         NOT NULL
               REFERENCES USER_ACCOUNT(user_id) ON DELETE CASCADE,
  plan_id    NUMBER         NOT NULL
               REFERENCES SUBSCRIPTION_PLAN(plan_id),
  start_date DATE           DEFAULT SYSDATE,
  end_date   DATE,          -- AUTO-CALCULATED by trg_calc_end_date
  status     VARCHAR2(15)   DEFAULT 'ACTIVE'
               CHECK (status IN ('ACTIVE','EXPIRED','CANCELLED'))
);

-- TABLE 4 : CONTENT
--   All movies and TV shows on the platform.
CREATE TABLE CONTENT (
  content_id   NUMBER         DEFAULT CONTENT_SEQ.NEXTVAL PRIMARY KEY,
  show_id      VARCHAR2(10)   UNIQUE,
  title        VARCHAR2(200)  NOT NULL,
  type         VARCHAR2(10)   CHECK (type IN ('MOVIE','SERIES')),
  director     VARCHAR2(200),
  cast_members VARCHAR2(500),
  country      VARCHAR2(100),
  release_year NUMBER(4),
  age_rating   VARCHAR2(10),
  duration_min NUMBER         DEFAULT 0,
  description  VARCHAR2(1000),
  rating_avg   NUMBER(3,1)    CHECK (rating_avg BETWEEN 0 AND 5)
);

-- TABLE 5 : GENRE
--   Normalised genre master (separated to satisfy 3NF).
CREATE TABLE GENRE (
  genre_id   NUMBER        DEFAULT GENRE_SEQ.NEXTVAL PRIMARY KEY,
  genre_name VARCHAR2(100) UNIQUE NOT NULL
);

-- TABLE 6 : CONTENT_GENRE  (M : N bridge)
--   Resolves the many-to-many relationship between CONTENT and GENRE.
CREATE TABLE CONTENT_GENRE (
  content_id NUMBER NOT NULL REFERENCES CONTENT(content_id)  ON DELETE CASCADE,
  genre_id   NUMBER NOT NULL REFERENCES GENRE(genre_id)      ON DELETE CASCADE,
  PRIMARY KEY (content_id, genre_id)
);

-- TABLE 7 : WATCH_HISTORY
--   Records every viewing event.
CREATE TABLE WATCH_HISTORY (
  watch_id     NUMBER         DEFAULT WATCH_SEQ.NEXTVAL PRIMARY KEY,
  user_id      NUMBER         NOT NULL REFERENCES USER_ACCOUNT(user_id) ON DELETE CASCADE,
  content_id   NUMBER         NOT NULL REFERENCES CONTENT(content_id)   ON DELETE CASCADE,
  watched_on   DATE           DEFAULT SYSDATE,
  progress_pct NUMBER(3)      DEFAULT 0
                 CHECK (progress_pct BETWEEN 0 AND 100)
);

-- TABLE 8 : RATING
--   User star-ratings for content (1–5).
CREATE TABLE RATING (
  rating_id    NUMBER         DEFAULT RATING_SEQ.NEXTVAL PRIMARY KEY,
  user_id      NUMBER         NOT NULL REFERENCES USER_ACCOUNT(user_id)  ON DELETE CASCADE,
  content_id   NUMBER         NOT NULL REFERENCES CONTENT(content_id)    ON DELETE CASCADE,
  rating_value NUMBER(1)      NOT NULL CHECK (rating_value BETWEEN 1 AND 5),
  rated_on     DATE           DEFAULT SYSDATE,
  UNIQUE (user_id, content_id)      -- one rating per user per title
);

-- TABLE 9 : PAYMENT
--   Automatically created by trigger when a subscription is activated.
CREATE TABLE PAYMENT (
  payment_id   NUMBER         DEFAULT PAYMENT_SEQ.NEXTVAL PRIMARY KEY,
  sub_id       NUMBER         NOT NULL
                 REFERENCES USER_SUBSCRIPTION(sub_id) ON DELETE CASCADE,
  amount       NUMBER(10,2)   NOT NULL,
  paid_on      DATE           DEFAULT SYSDATE,
  mode         VARCHAR2(15)   DEFAULT 'UPI'
                 CHECK (mode IN ('UPI','CARD','NETBANKING','WALLET'))
);

COMMIT;



-- SECTION 3 : PL/SQL TRIGGERS  (business logic in the database)


-- TRIGGER 1 : trg_calc_end_date
--   Fires BEFORE INSERT on USER_SUBSCRIPTION.
--   Automatically calculates End_Date from the plan's duration.
--   (The Java app never sends an end_date — the DB fills it.)
CREATE OR REPLACE TRIGGER trg_calc_end_date
BEFORE INSERT ON USER_SUBSCRIPTION
FOR EACH ROW
DECLARE
  v_days NUMBER;
BEGIN
  SELECT duration_days INTO v_days
  FROM   SUBSCRIPTION_PLAN
  WHERE  plan_id = :NEW.plan_id;

  :NEW.end_date := :NEW.start_date + v_days;

  DBMS_OUTPUT.PUT_LINE('[TRIGGER 1] trg_calc_end_date fired — end_date set to '
    || TO_CHAR(:NEW.end_date, 'DD-MON-YYYY'));
END;
/

-- TRIGGER 2 : trg_auto_payment
--   Fires AFTER INSERT on USER_SUBSCRIPTION.
--   Automatically inserts a payment record (no manual data entry).
CREATE OR REPLACE TRIGGER trg_auto_payment
AFTER INSERT ON USER_SUBSCRIPTION
FOR EACH ROW
DECLARE
  v_price NUMBER;
BEGIN
  SELECT price INTO v_price
  FROM   SUBSCRIPTION_PLAN
  WHERE  plan_id = :NEW.plan_id;

  INSERT INTO PAYMENT (sub_id, amount)
  VALUES (:NEW.sub_id, v_price);

  DBMS_OUTPUT.PUT_LINE('[TRIGGER 2] trg_auto_payment fired — Rs.'
    || v_price || ' recorded for sub_id=' || :NEW.sub_id);
END;
/

-- TRIGGER 3 : trg_expire_subscriptions
--   Fires BEFORE UPDATE or INSERT on USER_SUBSCRIPTION.
--   Marks a subscription EXPIRED if its end_date has passed.
CREATE OR REPLACE TRIGGER trg_expire_subscriptions
BEFORE UPDATE OR INSERT ON USER_SUBSCRIPTION
FOR EACH ROW
BEGIN
  IF :NEW.end_date IS NOT NULL AND :NEW.end_date < SYSDATE THEN
    :NEW.status := 'EXPIRED';
    DBMS_OUTPUT.PUT_LINE('[TRIGGER 3] trg_expire_subscriptions fired — status set to EXPIRED');
  END IF;
END;
/

COMMIT;



-- SECTION 4 : STORED PROCEDURES


-- PROCEDURE 1 : get_total_revenue
--   OUT parameter — returns the total amount collected across all payments.
--   Demonstrates stored procedure with output parameter.
CREATE OR REPLACE PROCEDURE get_total_revenue (p_total OUT NUMBER) IS
BEGIN
  SELECT NVL(SUM(amount), 0) INTO p_total FROM PAYMENT;
END;
/

-- PROCEDURE 2 : get_user_report
--   Accepts a user_id and returns the user's name, active plan,
--   subscription status, days remaining, and total watch time.
--   Demonstrates multi-value OUT parameter procedure.
CREATE OR REPLACE PROCEDURE get_user_report (
  p_user_id     IN  NUMBER,
  p_name        OUT VARCHAR2,
  p_plan        OUT VARCHAR2,
  p_status      OUT VARCHAR2,
  p_days_left   OUT NUMBER,
  p_watch_mins  OUT NUMBER
)
IS
BEGIN
  -- Subscription info
  SELECT ua.name, sp.plan_name, us.status,
         GREATEST(FLOOR(us.end_date - SYSDATE), 0)
  INTO   p_name, p_plan, p_status, p_days_left
  FROM   USER_ACCOUNT ua
  JOIN   USER_SUBSCRIPTION us ON ua.user_id = us.user_id
  JOIN   SUBSCRIPTION_PLAN sp ON us.plan_id = sp.plan_id
  WHERE  ua.user_id = p_user_id
    AND  us.status  = 'ACTIVE'
    AND  ROWNUM     = 1;

  -- Total watch time (in minutes)
  SELECT NVL(SUM(c.duration_min), 0)
  INTO   p_watch_mins
  FROM   WATCH_HISTORY wh
  JOIN   CONTENT c ON wh.content_id = c.content_id
  WHERE  wh.user_id = p_user_id;

EXCEPTION
  WHEN NO_DATA_FOUND THEN
    p_name       := 'User Not Found';
    p_plan       := 'N/A';
    p_status     := 'N/A';
    p_days_left  := 0;
    p_watch_mins := 0;
END;
/

COMMIT;



-- SECTION 5 : VIEWS


-- VIEW 1 : ACTIVE_SUBSCRIBERS_V
--   Shows all currently active subscribers with their plan details.
--   JOIN across USER_ACCOUNT, USER_SUBSCRIPTION, SUBSCRIPTION_PLAN.
CREATE OR REPLACE VIEW ACTIVE_SUBSCRIBERS_V AS
SELECT
  ua.user_id,
  ua.name,
  ua.email,
  sp.plan_name,
  sp.price         AS monthly_fee,
  sp.resolution,
  sp.max_devices,
  us.start_date,
  us.end_date,
  FLOOR(us.end_date - SYSDATE) AS days_remaining
FROM   USER_ACCOUNT      ua
JOIN   USER_SUBSCRIPTION us ON ua.user_id = us.user_id
JOIN   SUBSCRIPTION_PLAN sp ON us.plan_id = sp.plan_id
WHERE  us.status = 'ACTIVE';

-- VIEW 2 : CONTENT_STATS_V
--   Aggregates content information with user-rating counts and averages.
--   Uses LEFT JOIN to include content with no ratings yet.
CREATE OR REPLACE VIEW CONTENT_STATS_V AS
SELECT
  c.content_id,
  c.title,
  c.type,
  c.release_year,
  c.age_rating,
  c.duration_min,
  c.rating_avg     AS imdb_rating,
  COUNT(r.rating_id)            AS user_rating_count,
  ROUND(AVG(r.rating_value), 2) AS avg_user_rating
FROM   CONTENT c
LEFT JOIN RATING r ON c.content_id = r.content_id
GROUP BY c.content_id, c.title, c.type, c.release_year,
         c.age_rating, c.duration_min, c.rating_avg;

COMMIT;



-- SECTION 6 : MASTER DATA — Subscription Plans

INSERT INTO SUBSCRIPTION_PLAN VALUES (1, 'Mobile',   149,  30,  1, '480p',  'SD quality · 1 screen');
INSERT INTO SUBSCRIPTION_PLAN VALUES (2, 'Basic',    199,  30,  1, '720p',  'HD quality · 1 screen');
INSERT INTO SUBSCRIPTION_PLAN VALUES (3, 'Standard', 499,  30,  2, '1080p', 'Full HD · 2 screens');
INSERT INTO SUBSCRIPTION_PLAN VALUES (4, 'Premium',  649,  30,  4, '4K',    '4K + HDR · 4 screens');
INSERT INTO SUBSCRIPTION_PLAN VALUES (5, 'Annual',  2999, 365,  4, '4K',    '4K + HDR · Annual deal');
COMMIT;


 
-- SECTION 7 : GENRE DATA  (38 genres from the real Netflix dataset)

INSERT INTO GENRE (genre_id, genre_name) VALUES (1, 'Action & Adventure');
INSERT INTO GENRE (genre_id, genre_name) VALUES (2, 'Anime Features');
INSERT INTO GENRE (genre_id, genre_name) VALUES (3, 'Anime Series');
INSERT INTO GENRE (genre_id, genre_name) VALUES (4, 'British TV Shows');
INSERT INTO GENRE (genre_id, genre_name) VALUES (5, 'Children & Family Movies');
INSERT INTO GENRE (genre_id, genre_name) VALUES (6, 'Classic Movies');
INSERT INTO GENRE (genre_id, genre_name) VALUES (7, 'Comedies');
INSERT INTO GENRE (genre_id, genre_name) VALUES (8, 'Crime TV Shows');
INSERT INTO GENRE (genre_id, genre_name) VALUES (9, 'Cult Movies');
INSERT INTO GENRE (genre_id, genre_name) VALUES (10, 'Documentaries');
INSERT INTO GENRE (genre_id, genre_name) VALUES (11, 'Docuseries');
INSERT INTO GENRE (genre_id, genre_name) VALUES (12, 'Dramas');
INSERT INTO GENRE (genre_id, genre_name) VALUES (13, 'Faith & Spirituality');
INSERT INTO GENRE (genre_id, genre_name) VALUES (14, 'Horror Movies');
INSERT INTO GENRE (genre_id, genre_name) VALUES (15, 'Independent Movies');
INSERT INTO GENRE (genre_id, genre_name) VALUES (16, 'International Movies');
INSERT INTO GENRE (genre_id, genre_name) VALUES (17, 'International TV Shows');
INSERT INTO GENRE (genre_id, genre_name) VALUES (18, 'Kids'' TV');
INSERT INTO GENRE (genre_id, genre_name) VALUES (19, 'Korean TV Shows');
INSERT INTO GENRE (genre_id, genre_name) VALUES (20, 'LGBTQ Movies');
INSERT INTO GENRE (genre_id, genre_name) VALUES (21, 'Music & Musicals');
INSERT INTO GENRE (genre_id, genre_name) VALUES (22, 'Reality TV');
INSERT INTO GENRE (genre_id, genre_name) VALUES (23, 'Romantic Movies');
INSERT INTO GENRE (genre_id, genre_name) VALUES (24, 'Romantic TV Shows');
INSERT INTO GENRE (genre_id, genre_name) VALUES (25, 'Sci-Fi & Fantasy');
INSERT INTO GENRE (genre_id, genre_name) VALUES (26, 'Science & Nature TV');
INSERT INTO GENRE (genre_id, genre_name) VALUES (27, 'Spanish-Language TV Shows');
INSERT INTO GENRE (genre_id, genre_name) VALUES (28, 'Sports Movies');
INSERT INTO GENRE (genre_id, genre_name) VALUES (29, 'TV Action & Adventure');
INSERT INTO GENRE (genre_id, genre_name) VALUES (30, 'TV Comedies');
INSERT INTO GENRE (genre_id, genre_name) VALUES (31, 'TV Dramas');
INSERT INTO GENRE (genre_id, genre_name) VALUES (32, 'TV Horror');
INSERT INTO GENRE (genre_id, genre_name) VALUES (33, 'TV Mysteries');
INSERT INTO GENRE (genre_id, genre_name) VALUES (34, 'TV Sci-Fi & Fantasy');
INSERT INTO GENRE (genre_id, genre_name) VALUES (35, 'TV Shows');
INSERT INTO GENRE (genre_id, genre_name) VALUES (36, 'TV Thrillers');
INSERT INTO GENRE (genre_id, genre_name) VALUES (37, 'Teen TV Shows');
INSERT INTO GENRE (genre_id, genre_name) VALUES (38, 'Thrillers');
COMMIT;



-- ────────────────────────────────────────────────────────────────────
-- SECTION 8 : CONTENT DATA  (250 titles from Netflix dataset)
-- ────────────────────────────────────────────────────────────────────
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s1', 'Dick Johnson Is Dead', 'MOVIE', 'Kirsten Johnson', 'Various Artists', 'United States', 2020, 'PG-13', 90, 'As her father nears the end of his life, filmmaker Kirsten Johnson stages his death in inventive and comical ways to help them both face the inevitable.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s2', 'Blood & Water', 'SERIES', 'Unknown', 'Ama Qamata, Khosi Ngema, Gail Mabalane, Thabang Molaba, Dillon Windvogel, Natasha Thahane, Arno Greeff, Xolile Tshabalala, Getmore Sithole, Cindy Mahlangu, Ryle De Morny, Greteli Fincham, Sello Maake ', 'South Africa', 2021, 'TV-MA', 63, 'After crossing paths at a party, a Cape Town teen sets out to prove whether a private-school swimming star is her sister who was abducted at birth.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s3', 'Ganglands', 'SERIES', 'Julien Leclercq', 'Sami Bouajila, Tracy Gotoas, Samuel Jouy, Nabiha Akkari, Sofia Lesaffre, Salim Kechiouche, Noureddine Farihi, Geert Van Rampelberg, Bakary Diombera', 'International', 2021, 'TV-MA', 105, 'To protect his family from a powerful drug lord, skilled thief Mehdi and his expert team of robbers are pulled into a violent and deadly turf war.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s4', 'Jailbirds New Orleans', 'SERIES', 'Unknown', 'Various Artists', 'International', 2021, 'TV-MA', 78, 'Feuds, flirtations and toilet talk go down among the incarcerated women at the Orleans Justice Center in New Orleans on this gritty reality series.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s5', 'Kota Factory', 'SERIES', 'Unknown', 'Mayur More, Jitendra Kumar, Ranjan Raj, Alam Khan, Ahsaas Channa, Revathi Pillai, Urvi Singh, Arun Kumar', 'India', 2021, 'TV-MA', 162, 'In a city of coaching centers known to train India’s finest collegiate minds, an earnest but unexceptional student and his friends navigate campus life.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s6', 'Midnight Mass', 'SERIES', 'Mike Flanagan', 'Kate Siegel, Zach Gilford, Hamish Linklater, Henry Thomas, Kristin Lehman, Samantha Sloyan, Igby Rigney, Rahul Kohli, Annarah Cymone, Annabeth Gish, Alex Essoe, Rahul Abburi, Matt Biedel, Michael Truc', 'International', 2021, 'TV-MA', 141, 'The arrival of a charismatic young priest brings glorious miracles, ominous mysteries and renewed religious fervor to a dying town desperate to believe.', 3.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s7', 'My Little Pony: A New Generation', 'MOVIE', 'Robert Cullen, José Luis Ucha', 'Vanessa Hudgens, Kimiko Glenn, James Marsden, Sofia Carson, Liza Koshy, Ken Jeong, Elizabeth Perkins, Jane Krakowski, Michael McKean, Phil LaMarr', 'International', 2021, 'PG', 91, 'Equestria''s divided. But a bright-eyed hero believes Earth Ponies, Pegasi and Unicorns should be pals — and, hoof to heart, she’s determined to prove it.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s8', 'Sankofa', 'MOVIE', 'Haile Gerima', 'Kofi Ghanaba, Oyafunmike Ogunlano, Alexandra Duah, Nick Medley, Mutabaruka, Afemo Omilami, Reggie Carter, Mzuri', 'United States, Ghana, Burkina Faso, United Kingdom, Germany, Ethiopia', 1993, 'TV-MA', 125, 'On a photo shoot in Ghana, an American model slips back in time, becomes enslaved on a plantation and bears witness to the agony of her ancestral past.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s9', 'The Great British Baking Show', 'SERIES', 'Andy Devonshire', 'Mel Giedroyc, Sue Perkins, Mary Berry, Paul Hollywood', 'United Kingdom', 2021, 'TV-14', 174, 'A talented batch of amateur bakers face off in a 10-week competition, whipping up their best dishes in the hopes of being named the U.K.''s best.', 3.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s10', 'The Starling', 'MOVIE', 'Theodore Melfi', 'Melissa McCarthy, Chris O''Dowd, Kevin Kline, Timothy Olyphant, Daveed Diggs, Skyler Gisondo, Laura Harrier, Rosalind Chao, Kimberly Quinn, Loretta Devine, Ravi Kapoor', 'United States', 2021, 'PG-13', 104, 'A woman adjusting to life after a loss contends with a feisty bird that''s taken over her garden — and a husband who''s struggling to find a way forward.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s11', 'Vendetta: Truth, Lies and The Mafia', 'SERIES', 'Unknown', 'Various Artists', 'International', 2021, 'TV-MA', 162, 'Sicily boasts a bold "Anti-Mafia" coalition. But what happens when those trying to bring down organized crime are accused of being criminals themselves?', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s12', 'Bangkok Breaking', 'SERIES', 'Kongkiat Komesiri', 'Sukollawat Kanarot, Sushar Manaying, Pavarit Mongkolpisit, Sahajak Boonthanakit, Suthipongse Thatphithakkul, Bhasaworn Bawronkirati, Daweerit Chullasapya, Waratthaya Wongchayaporn, Kittiphoom Wongpent', 'International', 2021, 'TV-MA', 144, 'Struggling to earn a living in Bangkok, a man joins an emergency rescue service and realizes he must unravel a citywide conspiracy.', 4.4);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s13', 'Je Suis Karl', 'MOVIE', 'Christian Schwochow', 'Luna Wedler, Jannis Niewöhner, Milan Peschel, Edin Hasanović, Anna Fialová, Marlon Boess, Victor Boccard, Fleur Geffrier, Aziz Dyab, Mélanie Fouché, Elizaveta Maximová', 'Germany, Czech Republic', 2021, 'TV-MA', 127, 'After most of her family is murdered in a terrorist bombing, a young woman is unknowingly lured into joining the very group that killed them.', 4.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s14', 'Confessions of an Invisible Girl', 'MOVIE', 'Bruno Garotti', 'Klara Castanho, Lucca Picon, Júlia Gomes, Marcus Bessa, Kiria Malheiros, Fernanda Concon, Gabriel Lima, Caio Cabral, Leonardo Cidade, Jade Cardozo', 'International', 2021, 'TV-PG', 91, 'When the clever but socially-awkward Tetê joins a new school, she''ll do anything to fit in. But the queen bee among her classmates has other ideas.', 3.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s15', 'Crime Stories: India Detectives', 'SERIES', 'Unknown', 'Various Artists', 'International', 2021, 'TV-MA', 90, 'Cameras following Bengaluru police on the job offer a rare glimpse into the complex and challenging inner workings of four major crime investigations.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s16', 'Dear White People', 'SERIES', 'Unknown', 'Logan Browning, Brandon P. Bell, DeRon Horton, Antoinette Robertson, John Patrick Amedori, Ashley Blaine Featherson, Marque Richardson, Giancarlo Esposito', 'United States', 2021, 'TV-MA', 123, 'Students of color navigate the daily slights and slippery politics of life at an Ivy League college that''s not nearly as "post-racial" as it thinks.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s17', 'Europe''s Most Dangerous Man: Otto Skorzeny in Spain', 'MOVIE', 'Pedro de Echave García, Pablo Azorín Williams', 'Various Artists', 'International', 2020, 'TV-MA', 67, 'Declassified documents reveal the post-WWII life of Otto Skorzeny, a close Hitler ally who escaped to Spain and became an adviser to world presidents.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s18', 'Falsa identidad', 'SERIES', 'Unknown', 'Luis Ernesto Franco, Camila Sodi, Sergio Goyri, Samadhi Zendejas, Eduardo Yáñez, Sonya Smith, Alejandro Camacho, Azela Robinson, Uriel del Toro, Géraldine Bazán, Gabriela Roel, Marcus Ornellas', 'Mexico', 2020, 'TV-MA', 123, 'Strangers Diego and Isabel flee their home in Mexico and pretend to be a married couple to escape his drug-dealing enemies and her abusive husband.', 3.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s19', 'Intrusion', 'MOVIE', 'Adam Salky', 'Freida Pinto, Logan Marshall-Green, Robert John Burke, Megan Elisabeth Kelly, Sarah Minnich, Hayes Hargrove, Mark Sivertsen, Brandon Fierro, Antonio Valles, Clint Obenchain', 'International', 2021, 'TV-14', 94, 'After a deadly home invasion at a couple’s new dream house, the traumatized wife searches for answers — and learns the real danger is just beginning.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s20', 'Jaguar', 'SERIES', 'Unknown', 'Blanca Suárez, Iván Marcos, Óscar Casas, Adrián Lastra, Francesc Garrido, Stefan Weinert, Julia Möller, Alicia Chojnowski', 'International', 2021, 'TV-MA', 126, 'In the 1960s, a Holocaust survivor joins a group of self-trained spies who seek justice against Nazis fleeing to Spain to hide after WWII.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s21', 'Monsters Inside: The 24 Faces of Billy Milligan', 'SERIES', 'Olivier Megaton', 'Various Artists', 'International', 2021, 'TV-14', 174, 'In the late 1970s, an accused serial rapist claims multiple personalities control his behavior, setting off a legal odyssey that captivates America.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s22', 'Resurrection: Ertugrul', 'SERIES', 'Unknown', 'Engin Altan Düzyatan, Serdar Gökhan, Hülya Darcan, Kaan Taşaner, Esra Bilgiç, Osman Soykut, Serdar Deniz, Cengiz Coşkun, Reshad Strik, Hande Subaşı', 'Turkey', 2018, 'TV-14', 66, 'When a good deed unwittingly endangers his clan, a 13th-century Turkish warrior agrees to fight a sultan''s enemies in exchange for new tribal land.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s23', 'Avvai Shanmughi', 'MOVIE', 'K.S. Ravikumar', 'Kamal Hassan, Meena, Gemini Ganesan, Heera Rajgopal, Nassar, S.P. Balasubrahmanyam', 'International', 1996, 'TV-PG', 161, 'Newly divorced and denied visitation rights with his daughter, a doting father disguises himself as a gray-haired nanny in order to spend time with her.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s24', 'Go! Go! Cory Carson: Chrissy Takes the Wheel', 'MOVIE', 'Alex Woo, Stanley Moore', 'Maisie Benson, Paul Killam, Kerry Gudjohnsen, AC Lim', 'International', 2021, 'TV-Y', 61, 'From arcade games to sled days and hiccup cures, Cory Carson’s curious little sister Chrissy speeds off on her own for fun and adventure all over town!', 5.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s25', 'Jeans', 'MOVIE', 'S. Shankar', 'Prashanth, Aishwarya Rai Bachchan, Sri Lakshmi, Nassar', 'India', 1998, 'TV-14', 166, 'When the father of the man she loves insists that his twin sons marry twin sisters, a woman creates an alter ego that might be a bit too convincing.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s26', 'Love on the Spectrum', 'SERIES', 'Unknown', 'Brooke Satchwell', 'Australia', 2021, 'TV-14', 165, 'Finding love can be hard for anyone. For young adults on the autism spectrum, exploring the unpredictable world of dating is even more complicated.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s27', 'Minsara Kanavu', 'MOVIE', 'Rajiv Menon', 'Arvind Swamy, Kajol, Prabhu Deva, Nassar, S.P. Balasubrahmanyam, Girish Karnad', 'International', 1997, 'TV-PG', 147, 'A tangled love triangle ensues when a man falls for a woman studying to become a nun — and she falls for the friend he enlists to help him pursue her.', 4.4);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s28', 'Grown Ups', 'MOVIE', 'Dennis Dugan', 'Adam Sandler, Kevin James, Chris Rock, David Spade, Rob Schneider, Salma Hayek, Maria Bello, Maya Rudolph, Colin Quinn, Tim Meadows, Joyce Van Patten', 'United States', 2010, 'PG-13', 103, 'Mourning the loss of their beloved junior high basketball coach, five middle-aged pals reunite at a lake house and rediscover the joys of being a kid.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s29', 'Dark Skies', 'MOVIE', 'Scott Stewart', 'Keri Russell, Josh Hamilton, J.K. Simmons, Dakota Goyo, Kadan Rockett, L.J. Benet, Rich Hutchman, Myndy Crist, Annie Thurman, Jake Brennan', 'United States', 2013, 'PG-13', 97, 'A family’s idyllic suburban life shatters when an alien force invades their home, and as they struggle to convince others of the deadly threat.', 4.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s30', 'Paranoia', 'MOVIE', 'Robert Luketic', 'Liam Hemsworth, Gary Oldman, Amber Heard, Harrison Ford, Lucas Till, Embeth Davidtz, Julian McMahon, Josh Holloway, Richard Dreyfuss, Angela Sarafyan', 'United States, India, France', 2013, 'PG-13', 106, 'Blackmailed by his company''s CEO, a low-level employee finds himself forced to spy on the boss''s rival and former mentor.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s31', 'Ankahi Kahaniya', 'MOVIE', 'Ashwiny Iyer Tiwari, Abhishek Chaubey, Saket Chaudhary', 'Abhishek Banerjee, Rinku Rajguru, Delzad Hiwale, Kunal Kapoor, Zoya Hussain, Nikhil Dwivedi, Palomi Ghosh', 'International', 2021, 'TV-14', 111, 'As big city life buzzes around them, lonely souls discover surprising sources of connection and companionship in three tales of love, loss and longing.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s32', 'Chicago Party Aunt', 'SERIES', 'Unknown', 'Lauren Ash, Rory O''Malley, RuPaul Charles, Jill Talley, Ike Barinholtz, Jon Barinholtz, Matthew Craig, Bob Odenkirk, Mike Hagerty, Katie Rich, Chris Witaske', 'International', 2021, 'TV-MA', 102, 'Chicago Party Aunt Diane is an idolized troublemaker with a talent for avoiding adulthood — and a soft spot for her soul-searching nephew.', 4.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s33', 'Sex Education', 'SERIES', 'Unknown', 'Asa Butterfield, Gillian Anderson, Ncuti Gatwa, Emma Mackey, Connor Swindells, Kedar Williams-Stirling, Alistair Petrie', 'United Kingdom', 2020, 'TV-MA', 75, 'Insecure Otis has all the answers when it comes to sex advice, thanks to his therapist mom. So rebel Maeve proposes a school sex-therapy clinic.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s34', 'Squid Game', 'SERIES', 'Unknown', 'Lee Jung-jae, Park Hae-soo, Wi Ha-jun, Oh Young-soo, Jung Ho-yeon, Heo Sung-tae, Kim Joo-ryoung, Tripathi Anupam, You Seong-joo, Lee You-mi', 'International', 2021, 'TV-MA', 78, 'Hundreds of cash-strapped players accept a strange invitation to compete in children''s games. Inside, a tempting prize awaits — with deadly high stakes.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s35', 'Tayo and Little Wizards', 'SERIES', 'Unknown', 'Dami Lee, Jason Lee, Bommie Catherine Han, Jennifer Waescher, Nancy Kim', 'International', 2020, 'TV-Y7', 147, 'Tayo speeds into an adventure when his friends get kidnapped by evil magicians invading their city in search of a magical gemstone.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s36', 'The Father Who Moves Mountains', 'MOVIE', 'Daniel Sandu', 'Adrian Titieni, Elena Purea, Judith State, Valeriu Andriuță, Tudor Smoleanu, Virgil Aioanei, Radu Botar, Petronela Grigorescu, Bogdan Nechifor, Cristian Bota', 'International', 2021, 'TV-MA', 110, 'When his son goes missing during a snowy hike in the mountains, a retired intelligence officer will stop at nothing — and risk everything — to find him.', 4.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s37', 'The Stronghold', 'MOVIE', 'Cédric Jimenez', 'Gilles Lellouche, Karim Leklou, François Civil, Adèle Exarchopoulos, Kenza Fortas, Cyril Lecomte, Michaël Abiteboul, Idir Azougli, Vincent Darmuzey, Jean-Yves Berteloot', 'International', 2021, 'TV-MA', 105, 'Tired of the small-time grind, three Marseille cops get a chance to bust a major drug network. But lines blur when a key informant makes a big ask.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s38', 'Angry Birds', 'SERIES', 'Unknown', 'Antti Pääkkönen, Heljä Heikkinen, Lynne Guaglione, Pasi Ruohonen, Rauno Ahonen', 'Finland', 2018, 'TV-Y7', 99, 'Birds Red, Chuck and their feathered friends have lots of adventures while guarding eggs in their nest that pesky pigs keep trying to steal.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s39', 'Birth of the Dragon', 'MOVIE', 'George Nolfi', 'Billy Magnussen, Ron Yuan, Qu Jingjing, Terry Chen, Vanness Wu, Jin Xing, Philip Ng, Xia Yu, Yu Xia', 'China, Canada, United States', 2017, 'PG-13', 96, 'A young Bruce Lee angers kung fu traditionalists by teaching outsiders, leading to a showdown with a Shaolin master in this film based on real events.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s40', 'Chhota Bheem', 'SERIES', 'Unknown', 'Vatsal Dubey, Julie Tejwani, Rupa Bhimani, Jigna Bhardwaj, Rajesh Kava, Mousam, Swapnil', 'India', 2021, 'TV-Y7', 72, 'A brave, energetic little boy with superhuman powers leads his friends on exciting adventures to guard their fellow Dholakpur villagers from evil.', 4.4);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s41', 'He-Man and the Masters of the Universe', 'SERIES', 'Unknown', 'Yuri Lowenthal, Kimberly Brooks, Antony Del Rio, Trevor Devall, Ben Diskin, Grey Griffin, David Kaye, Tom Kenny, Judy Alice Lee, Roger Craig Smith, Fred Tatasciore', 'United States', 2021, 'TV-Y7', 90, 'Mighty teen Adam and his heroic squad of misfits discover the legendary power of Grayskull — and their destiny to defend Eternia from sinister Skeletor.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s42', 'Jaws', 'MOVIE', 'Steven Spielberg', 'Roy Scheider, Robert Shaw, Richard Dreyfuss, Lorraine Gary, Murray Hamilton, Carl Gottlieb, Jeffrey Kramer, Susan Backlinie, Jonathan Filley, Ted Grossman', 'United States', 1975, 'PG', 124, 'When an insatiable great white shark terrorizes Amity Island, a police chief, an oceanographer and a grizzled shark hunter seek to destroy the beast.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s43', 'Jaws 2', 'MOVIE', 'Jeannot Szwarc', 'Roy Scheider, Lorraine Gary, Murray Hamilton, Joseph Mascolo, Jeffrey Kramer, Collin Wilcox Paxton, Ann Dusenberry, Mark Gruner, Barry Coe, Susan French', 'United States', 1978, 'PG', 116, 'Four years after the last deadly shark attacks, police chief Martin Brody fights to protect Amity Island from another killer great white.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s44', 'Jaws 3', 'MOVIE', 'Joe Alves', 'Dennis Quaid, Bess Armstrong, Simon MacCorkindale, Louis Gossett Jr., John Putch, Lea Thompson, P.H. Moriarty, Dan Blasko, Liz Morris, Lisa Maurer', 'United States', 1983, 'PG', 98, 'After the staff of a marine theme park try to capture a young great white shark, they discover its mother has invaded the enclosure and is out for blood.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s45', 'Jaws: The Revenge', 'MOVIE', 'Joseph Sargent', 'Lorraine Gary, Lance Guest, Mario Van Peebles, Karen Young, Michael Caine, Judith Barsi, Mitchell Anderson, Lynn Whitfield', 'United States', 1987, 'PG-13', 91, 'After another deadly shark attack, Ellen Brody has had enough of Amity Island and moves to the Caribbean – but a great white shark follows her there.', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s46', 'My Heroes Were Cowboys', 'MOVIE', 'Tyler Greco', 'Various Artists', 'International', 2021, 'PG', 23, 'Robin Wiltshire''s painful childhood was rescued by Westerns. Now he lives on the frontier of his dreams, training the horses he loves for the big screen.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s47', 'Safe House', 'MOVIE', 'Daniel Espinosa', 'Denzel Washington, Ryan Reynolds, Vera Farmiga, Brendan Gleeson, Sam Shepard, Rubén Blades, Nora Arnezeder, Robert Patrick, Liam Cunningham, Joel Kinnaman', 'South Africa, United States, Japan', 2012, 'R', 115, 'Young CIA operative Matt Weston must get a dangerous criminal out of an agency safe house that''s come under attack and get him to a securer location.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s48', 'The Smart Money Woman', 'SERIES', 'Bunmi Ajakaiye', 'Osas Ighodaro, Ini Dima-Okojie, Kemi Lala Akindoju, Toni Tones, Ebenezer Eno, Eso Okolocha DIke, Patrick Diabuah, Karibi Fubara, Temisan Emmanuel, Timini Egbuson', 'International', 2020, 'TV-MA', 120, 'Five glamorous millennials strive for success as they juggle careers, finances, love and friendships. Based on Arese Ugwu''s 2016 best-selling novel.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s49', 'Training Day', 'MOVIE', 'Antoine Fuqua', 'Denzel Washington, Ethan Hawke, Scott Glenn, Tom Berenger, Harris Yulin, Raymond J. Barry, Cliff Curtis, Dr. Dre, Snoop Dogg, Macy Gray, Eva Mendes', 'United States', 2001, 'R', 122, 'A rookie cop with one day to prove himself to a veteran LAPD narcotics officer receives a crash course in his mentor''s questionable brand of justice.', 4.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s50', 'Castle and Castle', 'SERIES', 'Unknown', 'Richard Mofe-Damijo, Dakore Akande, Bimbo Manuel, Blossom Chukwujekwu, Deyemi Okanlawon, Etim Effiong, Denola Grey, Duke Akintola, Eku Edewor, Ade Laoye, Anee Icha, Kevin Ushi, Jude Chukwuka, Amanda A', 'Nigeria', 2021, 'TV-MA', 102, 'A pair of high-powered, successful lawyers find themselves defending opposite interests of the justice system, causing a strain on their happy marriage.', 4.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s51', 'Dharmakshetra', 'SERIES', 'Unknown', 'Kashmira Irani, Chandan Anand, Dinesh Mehta, Ankit Arora, Pushkar Goggiaa, Anjali Rana, Aarya DharmChand Kumar, Amit Behl, Maleeka Ghai', 'India', 2014, 'TV-PG', 120, 'After the ancient Great War, the god Chitragupta oversees a trial to determine who were the battle''s true heroes and villains.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s52', 'InuYasha the Movie 2: The Castle Beyond the Looking Glass', 'MOVIE', 'Toshiya Shinohara', 'Kappei Yamaguchi, Satsuki Yukino, Mieko Harada, Koji Tsujitani, Houko Kuwashima, Kumiko Watanabe, Noriko Hidaka, Kenichi Ogata, Toshiyuki Morikawa, Izumi Ogami', 'Japan', 2002, 'TV-14', 99, 'With their biggest foe seemingly defeated, InuYasha and his friends return to everyday life. But the peace is soon shattered by an emerging new enemy.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s53', 'InuYasha the Movie 3: Swords of an Honorable Ruler', 'MOVIE', 'Toshiya Shinohara', 'Kappei Yamaguchi, Satsuki Yukino, Koji Tsujitani, Houko Kuwashima, Kumiko Watanabe, Ken Narita, Akio Otsuka, Kikuko Inoue', 'Japan', 2003, 'TV-14', 99, 'The Great Dog Demon beaqueathed one of the Three Swords of the Fang to each of his two sons. Now the evil power of the third sword has been awakened.', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s54', 'InuYasha the Movie 4: Fire on the Mystic Island', 'MOVIE', 'Toshiya Shinohara', 'Kappei Yamaguchi, Satsuki Yukino, Koji Tsujitani, Houko Kuwashima, Kumiko Watanabe, Noriko Hidaka, Ken Narita, Cho, Mamiko Noto, Nobutoshi Canna', 'Japan', 2004, 'TV-PG', 88, 'Ai, a young half-demon who has escaped from Horai Island to try to help her people, returns with potential saviors InuYasha, Sesshomaru and Kikyo.', 4.4);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s55', 'InuYasha the Movie: Affections Touching Across Time', 'MOVIE', 'Toshiya Shinohara', 'Kappei Yamaguchi, Satsuki Yukino, Koji Tsujitani, Houko Kuwashima, Kumiko Watanabe, Kenichi Ogata, Noriko Hidaka, Hisako Kyoda, Ken Narita, Tomokazu Seki', 'Japan', 2001, 'TV-PG', 100, 'A powerful demon has been sealed away for 200 years. But when the demon''s son is awakened, the fate of the world is in jeopardy.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s56', 'Nailed It', 'SERIES', 'Unknown', 'Nicole Byer, Jacques Torres', 'United States', 2021, 'TV-PG', 99, 'Home bakers with a terrible track record take a crack at re-creating edible masterpieces for a $10,000 prize. It''s part reality contest, part hot mess.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s57', 'Naruto Shippuden the Movie: Blood Prison', 'MOVIE', 'Masahiko Murata', 'Junko Takeuchi, Chie Nakamura, Rikiya Koyama, Kazuhiko Inoue, Masaki Terasoma, Mie Sonozaki, Yuichi Nakamura, Kengo Kawanishi, Kosei Hirota, Masako Katsuki', 'Japan', 2011, 'TV-14', 102, 'Mistakenly accused of an attack on the Fourth Raikage, ninja Naruto is imprisoned in the impenetrable Hozuki Castle and his powers are sealed.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s58', 'Naruto Shippûden the Movie: Bonds', 'MOVIE', 'Hajime Kamegaki', 'Junko Takeuchi, Chie Nakamura, Noriaki Sugiyama, Unsho Ishizuka, Motoko Kumai, Kazuhiko Inoue, Rikiya Koyama, Showtaro Morikubo, Nana Mizuki, Satoshi Hino, Shinji Kawada', 'Japan', 2008, 'TV-PG', 93, 'When strange ninjas ambush the village of Konohagakure, it''s up to adolescent ninja Naruto and his long-missing pal, Sasuke, to save the planet.', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s59', 'Naruto Shippûden the Movie: The Will of Fire', 'MOVIE', 'Masahiko Murata', 'Junko Takeuchi, Chie Nakamura, Kazuhiko Inoue, Satoshi Hino, Showtaro Morikubo, Kentaro Ito, Ryoka Yuzuki, Kohsuke Toriumi, Nana Mizuki, Shinji Kawada, Yoichi Masukawa, Koichi Tochika, Yukari Tamura', 'Japan', 2009, 'TV-PG', 96, 'When four out of five ninja villages are destroyed, the leader of the one spared tries to find the true culprit and protect his land.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s60', 'Naruto Shippuden: The Movie', 'MOVIE', 'Hajime Kamegaki', 'Junko Takeuchi, Chie Nakamura, Yoichi Masukawa, Koichi Tochika, Ayumi Fujimura, Keisuke Oda, Daisuke Kishio, Fumiko Orikasa, Hidetoshi Nakamura, Tetsuya Kakihara, Kisho Taniyama, Miyuki Sawashiro, Kat', 'Japan', 2007, 'TV-PG', 95, 'The adventures of adolescent ninja Naruto Uzumaki continue as he''s tasked with protecting a priestess from a demon – but to do so, he must die.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s61', 'Naruto Shippuden: The Movie: The Lost Tower', 'MOVIE', 'Masahiko Murata', 'Junko Takeuchi, Chie Nakamura, Satoshi Hino, Rikiya Koyama, Nobuaki Fukuda, Kenji Hamada, Keiko Nemoto, Saori Hayami, Yumi Toma, Yuko Kobayashi, Fujiko Takimoto, Mutsumi Tamura, Mayuki Makiguchi, Tosh', 'Japan', 2010, 'TV-14', 85, 'When Naruto is sent to recover a missing nin, the rogue manages to send him 20 years into the past, where he unites with his father to battle evil.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s62', 'Naruto the Movie 2: Legend of the Stone of Gelel', 'MOVIE', 'Hirotsugu Kawasaki', 'Junko Takeuchi, Gamon Kaai, Chie Nakamura, Showtaro Morikubo, Akira Ishida, Yasuyuki Kase, Urara Takano, Sachiko Kojima, Houko Kuwashima, Takako Honda', 'Japan', 2005, 'TV-PG', 97, 'While on a mission to return a missing pet, Naruto and two fellow ninjas are ambushed by brutal knights led by the enigmatic Temujin.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s63', 'Naruto the Movie 3: Guardians of the Crescent Moon Kingdom', 'MOVIE', 'Toshiyuki Tsuru', 'Junko Takeuchi, Chie Nakamura, Yoichi Masukawa, Kazuhiko Inoue, Akio Otsuka, Kyousuke Ikeda, Marika Hayashi, Umeji Sasaki, Masashi Sugawara, Hisao Egawa', 'Japan', 2006, 'TV-PG', 95, 'Exuberant ninja Naruto teams up with his pals Sakura and Kakashi to escort Prince Michiru and his son, Hikaru, to the Crescent Moon kingdom.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s64', 'Naruto the Movie: Ninja Clash in the Land of Snow', 'MOVIE', 'Tensai Okamura', 'Junko Takeuchi, Noriaki Sugiyama, Chie Nakamura, Kazuhiko Inoue, Yuhko Kaida, Tsutomu Isobe, Hirotaka Suzuoki, Jun Karasawa, Harii Kaneko, Ikuo Nishikawa', 'Japan', 2004, 'TV-PG', 83, 'Naruto, Sasuke and Sakura learn they''ll be protecting an actress from being hurt while making her next film, but it turns out she''s a princess.', 4.4);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s65', 'Nightbooks', 'MOVIE', 'David Yarovesky', 'Winslow Fegley, Lidya Jewett, Krysten Ritter', 'International', 2021, 'TV-PG', 103, 'Scary story fan Alex must tell a spine-tingling tale every night — or stay trapped with his new friend in a wicked witch''s magical apartment forever.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s66', 'Numberblocks', 'SERIES', 'Unknown', 'Beth Chalmers, David Holt, Marcel McCalla, Teresa Gallagher', 'United Kingdom', 2021, 'TV-Y', 135, 'In a place called Numberland, math adds up to tons of fun when a group of cheerful blocks work, play and sing together.', 4.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s67', 'Raja Rasoi Aur Anya Kahaniyan', 'SERIES', 'Unknown', 'Various Artists', 'India', 2014, 'TV-G', 84, 'Explore the history and flavors of regional Indian cuisine, from traditional Kashmiri feasts to the vegetarian dishes of Gujarat.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s68', 'Saved by the Bell', 'SERIES', 'Unknown', 'Mark-Paul Gosselaar, Tiffani Thiessen, Mario Lopez, Lark Voorhies, Elizabeth Berkley, Dustin Diamond, Dennis Haskins', 'United States', 1994, 'TV-PG', 75, 'From middle school to college, best friends Zack, Kelly, Slater, Jessie, Screech and Lisa take on the highs and lows of life together in this hit series.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s69', 'Schumacher', 'MOVIE', 'Hanns-Bruno Kammertöns, Vanessa Nöcker, Michael Wech', 'Michael Schumacher', 'International', 2021, 'TV-14', 113, 'Through exclusive interviews and archival footage, this documentary traces an intimate portrait of seven-time Formula 1 champion Michael Schumacher.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s70', 'Stories by Rabindranath Tagore', 'SERIES', 'Unknown', 'Various Artists', 'India', 2015, 'TV-PG', 87, 'The writings of Nobel Prize winner Rabindranath Tagore come to life in this collection of tales set in early-20th-century Bengal.', 4.4);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s71', 'Too Hot To Handle: Latino', 'SERIES', 'Unknown', 'Itatí Cantoral', 'International', 2021, 'TV-MA', 141, 'On this reality show, singles from Latin America and Spain are challenged to give up sex. But here, abstinence comes with a silver lining: US$100,000.', 4.4);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s72', 'A StoryBots Space Adventure', 'MOVIE', 'David A. Vargas', 'Evan Spiridellis, Erin Fitzgerald, Jeff Gill, Fred Tatasciore, Evan Michael Lee, Jared Isaacman, Sian Proctor, Chris Sembroski, Hayley Arceneaux', 'International', 2021, 'TV-Y', 13, 'Join the StoryBots and the space travelers of the historic Inspiration4 mission as they search for answers to kids'' questions about space.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s73', 'Jack Whitehall: Travels with My Father', 'SERIES', 'Unknown', 'Jack Whitehall, Michael Whitehall', 'United Kingdom', 2021, 'TV-MA', 174, 'Jovial comic Jack Whitehall invites his stuffy father, Michael, to travel with him through Southeast Asia in an attempt to strengthen their bond.', 5.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s74', 'King of Boys', 'MOVIE', 'Kemi Adetiba', 'Sola Sobowale, Adesua Etomi, Remilekun "Reminisce" Safaru, Tobechukwu "iLLbliss" Ejiofor, Toni Tones, Paul Sambo, Jide Kosoko, Sharon Ooja', 'Nigeria', 2018, 'TV-MA', 182, 'When a powerful businesswoman’s political ambitions are threatened by her underworld connections, the ensuing power struggle could cost her everything.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s75', 'The World''s Most Amazing Vacation Rentals', 'SERIES', 'Unknown', 'Various Artists', 'International', 2021, 'TV-PG', 165, 'With an eye for every budget, three travelers visit vacation rentals around the globe and share their expert tips and tricks in this reality series.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s76', 'You vs. Wild: Out Cold', 'MOVIE', 'Ben Simms', 'Bear Grylls, Jason Derek Prempeh', 'International', 2021, 'TV-G', 106, 'After a plane crash leaves Bear with amnesia, he must make choices to save the missing pilot and survive in this high-stakes interactive adventure.', 3.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s77', 'Yowamushi Pedal', 'SERIES', 'Unknown', 'Daiki Yamashita, Kohsuke Toriumi, Jun Fukushima, Hiroki Yasumoto, Showtaro Morikubo, Kentaro Ito, Daisuke Kishio, Yoshitsugu Matsuoka, Junichi Suwabe, Ayaka Suwa, Megumi Han, Tomoaki Maeno, Tsubasa Yo', 'Japan', 2013, 'TV-14', 81, 'A timid, anime-loving teen gets drawn into a school cycling club, where his new friends help him face tough challenges to develop his racing talent.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s78', 'Little Singham - Black Shadow', 'MOVIE', 'Prakash Satam', 'Sumriddhi Shukla, Jigna Bharadwaj, Sonal Kaushal, Neshma Chemburkar, Ganesh Divekar, Annamaya Verma, Anamay Verma, Manoj Pandey', 'International', 2021, 'TV-Y7', 48, 'Kid cop Little Singham loses all his superpowers while trying to stop the demon Kaal’s new evil plans! Can his inner strength help him defeat the enemy?', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s79', 'Tughlaq Durbar', 'MOVIE', 'Delhiprasad Deenadayalan', 'Vijay Sethupathi, Parthiban, Raashi Khanna', 'International', 2020, 'TV-14', 145, 'A budding politician has devious plans to rise in the ranks — until an unexpected new presence begins to interfere with his every crooked move.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s80', 'Tughlaq Durbar (Telugu)', 'MOVIE', 'Delhiprasad Deenadayalan', 'Vijay Sethupathi, Parthiban, Raashi Khanna', 'International', 2021, 'TV-14', 145, 'A budding politician has devious plans to rise in the ranks — until an unexpected new presence begins to interfere with his every crooked move.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s81', 'Firedrake the Silver Dragon', 'MOVIE', 'Tomer Eshed', 'Thomas Brodie-Sangster, Felicity Jones, Freddie Highmore, Patrick Stewart, Meera Syal, Sanjeev Bhaskar, Nonso Anozie', 'International', 2021, 'TV-Y7', 93, 'When his home is threatened by humans, a young dragon summons the courage to seek a mythical paradise where dragons can live in peace and fly free.', 3.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s82', 'Kate', 'MOVIE', 'Cedric Nicolas-Troyan', 'Mary Elizabeth Winstead, Jun Kunimura, Woody Harrelson, Tadanobu Asano, Miyavi, Michiel Huisman, Miku Martineau', 'United States', 2021, 'R', 106, 'Slipped a fatal poison on her final job, a ruthless assassin working in Tokyo has less than 24 hours to find out who ordered the hit and exact revenge.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s83', 'Lucifer', 'SERIES', 'Unknown', 'Tom Ellis, Lauren German, Kevin Alejandro, D.B. Woodside, Lesley-Ann Brandt, Scarlett Estevez, Rachael Harris, Aimee Garcia, Tricia Helfer, Tom Welling, Jeremiah W. Birkett, Pej Vahdat, Michael Gladis', 'United States', 2021, 'TV-14', 147, 'Bored with being the Lord of Hell, the devil relocates to Los Angeles, where he opens a nightclub and forms a connection with a homicide detective.', 3.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s84', 'Metal Shop Masters', 'SERIES', 'Unknown', 'Jo Koy', 'International', 2021, 'TV-MA', 108, 'On this competition show, a group of metal artists torch, cut and weld epic, badass creations from hardened steel. Only one will win a $50,000 prize.', 5.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s85', 'Omo Ghetto: the Saga', 'MOVIE', 'JJC Skillz, Funke Akindele', 'Funke Akindele, Ayo Makun, Chioma Chukwuka Akpotha, Yemi Eberechi Alade, Blossom Chukwujekwu, Deyemi Okanlawon, Alexx Ekubo, Zubby Michael, Tina Mba, Femi Jacobs', 'Nigeria', 2020, 'TV-MA', 147, 'Twins are reunited as a good-hearted female gangster and her uptight rich sister take on family, crime, cops and all of the trouble that follows them.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s86', 'Pokémon Master Journeys: The Series', 'SERIES', 'Unknown', 'Ikue Otani, Sarah Natochenny, Zeno Robinson, Cherami Leigh, James Carter Cathcart, Michele Knotz, Rodger Parsons, Ray Chase, Casey Mongillo, Tara Sands', 'International', 2021, 'TV-Y7', 156, 'As Ash battles his way through the World Coronation Series, Goh continues his quest to catch every Pokémon. Together, they''re on a journey to adventure!', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s87', 'Prey', 'MOVIE', 'Thomas Sieben', 'David Kross, Hanno Koffler, Maria Ehrich, Robert Finster, Yung Ngo, Klaus Steinbacher, Livia Matthes, Nellie Thalbach', 'International', 2021, 'TV-MA', 87, 'A hiking trip into the wild turns into a desperate bid for survival for five friends on the run from a mysterious shooter.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s88', 'Titipo Titipo', 'SERIES', 'Unknown', 'Jeon Hae-ri, Kim Eun-ah, Hong Bum-ki, Nam Do-hyeong, Um Sang-hyun', 'International', 2019, 'TV-Y', 117, 'Titipo the train is out to prove that he''s got what it takes to help the folks of Train Village ride the rails safely and reliably.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s89', 'Blood Brothers: Malcolm X & Muhammad Ali', 'MOVIE', 'Marcus Clarke', 'Malcolm X, Muhammad Ali', 'International', 2021, 'PG-13', 96, 'From a chance meeting to a tragic fallout, Malcolm X and Muhammad Ali''s extraordinary bond cracks under the weight of distrust and shifting ideals.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s90', 'Mighty Raju', 'SERIES', 'Unknown', 'Julie Tejwani, Sabina Malik, Jigna Bhardwaj, Rupa Bhimani, Lalit Agarwal, Rajesh Shukla, Rajesh Kava', 'International', 2017, 'TV-Y7', 96, 'Born with superhuman abilities, young Raju wants to use his powers to make the world a better place — but that will mean facing plenty of challenges!', 3.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s91', 'Paradise Hills', 'MOVIE', 'Alice Waddington', 'Emma Roberts, Danielle Macdonald, Awkwafina, Eiza González, Milla Jovovich, Jeremy Irvine, Arnaud Valois, Daniel Horvath', 'Spain, United States', 2019, 'TV-MA', 95, 'Uma wakes up in a lush tropical facility designed to turn willful girls into perfect ladies. That’s bad enough, but its real purpose is even worse.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s92', 'The Women and the Murderer', 'MOVIE', 'Mona Achache, Patricia Tourancheau', 'Various Artists', 'France', 2021, 'TV-14', 92, 'This documentary traces the capture of serial killer Guy Georges through the tireless work of two women: a police chief and a victim''s mother.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s93', 'Into the Night', 'SERIES', 'Unknown', 'Pauline Etienne, Laurent Capelluto, Stefano Cassetti, Mehmet Kurtuluş, Babetida Sadjo, Jan Bijvoet, Ksawery Szlenkier, Vincent Londez, Regina Bikkinina, Alba Gaïa Kraghede Bellugi, Nabil Mallat', 'Belgium', 2021, 'TV-MA', 159, 'Passengers and crew aboard a hijacked overnight flight scramble to outrace the sun as a mysterious cosmic event wreaks havoc on the world below.', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s94', 'JJ+E', 'MOVIE', 'Alexis Almström', 'Elsa Öhrn, Mustapha Aarab, Jonay Pineda Skallak, Magnus Krepper, Loreen, Albin Grenholm, Simon Mezher, Elsa Bergström Terent, Josef Kadim, Yohannes Frezgi', 'International', 2021, 'TV-MA', 91, 'Elisabeth and John-John live in the same city, but they inhabit different worlds. Can a passionate first love break through class and cultural barriers?', 4.4);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s95', 'Show Dogs', 'MOVIE', 'Raja Gosnell', 'Will Arnett, Ludacris, Natasha Lyonne, Stanley Tucci, Jordin Sparks, Gabriel Iglesias, Shaquille O''Neal, Omar Chaparro, Alan Cumming, Andy Beckwith, Delia Sheppard, Kerry Shale', 'United Kingdom, United States', 2018, 'PG', 90, 'A rough and tough police dog must go undercover with an FBI agent as a prim and proper pet at a dog show to save a baby panda from an illegal sale.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s96', 'The Circle', 'SERIES', 'Unknown', 'Michelle Buteau', 'United States, United Kingdom', 2021, 'TV-MA', 81, 'Status and strategy collide in this social experiment and competition show where online players flirt, befriend and catfish their way toward $100,000.', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s97', 'If I Leave Here Tomorrow: A Film About Lynyrd Skynyrd', 'MOVIE', 'Stephen Kijak', 'Ronnie Van Zandt, Gary Rossington, Allen Collins, Leon Wilkeson, Bob Burns, Billy Powell, Ed King, Artimus Pyle, Steve Gaines, Johnny Van Zant', 'United States', 2018, 'TV-MA', 97, 'Using interviews and archival footage, this documentary charts the story of the legendary Southern rockers with a focus on front man Ronnie Van Zant.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s98', 'Kid Cosmic', 'SERIES', 'Unknown', 'Jack Fisher, Tom Kenny, Amanda C. Miller, Kim Yarbrough, Keith Ferguson, Grey Griffin, Lily Rose Silver', 'United States', 2021, 'TV-Y7', 117, 'A boy''s superhero dreams come true when he finds five powerful cosmic stones. But saving the day is harder than he imagined — and he can''t do it alone.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s99', 'Octonauts: Above & Beyond', 'SERIES', 'Unknown', 'Antonio Aakeel, Chipo Chung, Simon Foster, Teresa Gallagher, Simon Greenall, Kate Harbour, Paul Panting, Rob Rackstraw, William Vanderpuye, Helen Walsh, Keith Wickham, Andres Williams, Jo Wyatt', 'United Kingdom', 2021, 'TV-Y', 105, 'The Octonauts expand their exploration beyond the sea — and onto land! With new rides and new friends, they''ll protect any habitats and animals at risk.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s100', 'On the Verge', 'SERIES', 'Unknown', 'Julie Delpy, Elisabeth Shue, Sarah Jones, Alexia Landeau, Mathieu Demy, Troy Garity, Timm Sharp, Giovanni Ribisi', 'France, United States', 2021, 'TV-MA', 75, 'Four women — a chef, a single mom, an heiress and a job seeker — dig into love and work, with a generous side of midlife crises, in pre-pandemic LA.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s101', 'Tobot Galaxy Detectives', 'SERIES', 'Unknown', 'Austin Abell, Travis Turner, Cole Howard, Anna Cummer, Jesse Inocalla, Brian Dobson, Michael Adamthwaite, Joseph Girgis, Caitlyn Bairstow', 'International', 2019, 'TV-Y7', 153, 'An intergalactic device transforms toy cars into robots: the Tobots! Working with friends to solve mysteries, they protect the world from evil.', 4.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s102', 'Untold: Breaking Point', 'MOVIE', 'Chapman Way, Maclain Way', 'Various Artists', 'United States', 2021, 'TV-MA', 80, 'Under pressure to continue a winning tradition in American tennis, Mardy Fish faced mental health challenges that changed his life on and off the court.', 5.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s103', 'Countdown: Inspiration4 Mission to Space', 'SERIES', 'Jason Hehir', 'Various Artists', 'International', 2021, 'TV-14', 162, 'From training to launch to landing, this all-access docuseries rides along with the Inspiration4 crew on the first all-civilian orbital space mission.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s104', 'Shadow Parties', 'MOVIE', 'Yemi Amodu', 'Jide Kosoko, Omotola Jalade-Ekeinde, Yemi Blaq, Sola Sobowale, Ken Erics, Toyin Aimakhu, Segun Arinze, Jibola Dabo, Rotimi Salami, Pa Jimi Solanke, Rachael Okonkwo, Bassey Okon, Lucien Morgan, Magdale', 'International', 2020, 'TV-MA', 117, 'A family faces destruction in a long-running conflict between communities that pits relatives against each other amid attacks and reprisals.', 3.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s105', 'Tayo the Little Bus', 'SERIES', 'Unknown', 'Robyn Slade, Kami Desilets', 'South Korea', 2016, 'TV-Y', 150, 'As they learn their routes around the busy city, Tayo and his little bus friends discover new sights and go on exciting adventures every day.', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s106', 'Angamaly Diaries', 'MOVIE', 'Lijo Jose Pellissery', 'Antony Varghese, Reshma Rajan, Binny Rinky Benjamin, Vineeth Vishwam, Kichu Tellus, Sreekanth Dasan, Sarath Kumar, Tito Wilson, Anandhu, Bitto Davis, Sinoj Varghese', 'India', 2017, 'TV-14', 128, 'After growing up amidst the gang wars of his hometown, Vincent forms an entrepreneurial squad of his own and ends up on the wrong side of the law.', 3.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s107', 'Bunk''d', 'SERIES', 'Unknown', 'Peyton List, Karan Brar, Skai Jackson, Miranda May, Kevin G. Quinn, Nathan Arenas, Nina Lu', 'United States', 2021, 'TV-G', 159, 'The Ross siblings of Disney''s hit series "Jessie" spend a summer full of fun and adventure at Maine''s Camp Kikiwaka, where their parents first met.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s108', 'A Champion Heart', 'MOVIE', 'David de Vos', 'Mandy Grace, David de Vos, Donna Rusch, Devan Key, Isabella Mancuso, Ariana Guido', 'United States', 2018, 'G', 90, 'When a grieving teen must work off her debt to a ranch, she cares for a wounded horse that teaches her more about healing than she expected.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s109', 'Dive Club', 'SERIES', 'Unknown', 'Aubri Ibrag, Sana''a Shaik, Miah Madden, Mercy Cornwall, Georgia-May Davis, Ryan Harrison, Josh Heuston, Alexander Grant', 'Australia', 2021, 'TV-G', 99, 'On the shores of Cape Mercy, a skillful group of teen divers investigate a series of secrets and signs after one of their own mysteriously goes missing.', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s110', 'La casa de papel', 'SERIES', 'Unknown', 'Úrsula Corberó, Itziar Ituño, Álvaro Morte, Paco Tous, Enrique Arce, Pedro Alonso, María Pedraza, Alba Flores, Miguel Herrán, Jaime Lorente, Esther Acebo, Darko Peric, Kiti Mánver', 'Spain', 2021, 'TV-MA', 96, 'Eight thieves take hostages and lock themselves in the Royal Mint of Spain as a criminal mastermind manipulates the police to carry out his plan.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s111', 'Money Heist: From Tokyo to Berlin', 'SERIES', 'Luis Alfaro, Javier Gómez Santander', 'Various Artists', 'International', 2021, 'TV-MA', 135, 'The filmmakers and actors behind "Money Heist" characters like Tokyo and the Professor talk about the emotional artistic process of filming the series.', 5.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s112', 'Sharkdog', 'SERIES', 'Unknown', 'Liam Mitchell, Dee Bradley Baker, Grey Griffin, Josh McDermitt, Kari Wahlgren, Judy Alice Lee, Ali Mawji', 'United States, Singapore', 2021, 'TV-Y', 129, 'Half shark, half dog with a big heart and a belly full of fish sticks! Together, Sharkdog and his human pal Max can take on any silly or messy adventure.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s113', 'Worth', 'MOVIE', 'Sara Colangelo', 'Michael Keaton, Stanley Tucci, Amy Ryan, Shunori Ramanathan, Ato Blankson-Wood, Tate Donovan, Laura Benanti, Chris Tardio', 'International', 2021, 'PG-13', 119, 'In the wake of the Sept. 11 attacks, a lawyer faces an emotional reckoning as he attempts to put a dollar value on the lives lost. Based on real events.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s114', 'Afterlife of the Party', 'MOVIE', 'Stephen Herek', 'Victoria Justice, Midori Francis, Robyn Scott, Adam Garcia, Timothy Renouf, Gloria Garcia, Myfanwy Waring, Spencer Sutherland', 'International', 2021, 'TV-PG', 110, 'Cassie lives to party... until she dies in a freak accident. Now this social butterfly needs to right her wrongs on Earth if she wants to earn her wings.', 3.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s115', 'Anjaam', 'MOVIE', 'Rahul Rawail', 'Madhuri Dixit, Shah Rukh Khan, Tinnu Anand, Johny Lever, Kalpana Iyer, Himani Shivpuri, Sudha Chandran, Beena, Kiran Kumar', 'India', 1994, 'TV-14', 143, 'A wealthy industrialist’s dangerous obsession with a flight attendant destroys her world, until she takes matters into her own hands to exact revenge.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s116', 'Bright Star', 'MOVIE', 'Jane Campion', 'Abbie Cornish, Ben Whishaw, Paul Schneider, Kerry Fox, Edie Martin, Thomas Brodie-Sangster, Claudie Blakley, Gerard Monaco, Antonia Campbell-Hughes, Samuel Roukin', 'United Kingdom, Australia, France', 2009, 'PG', 119, 'This drama details the passionate three-year romance between Romantic poet John Keats – who died tragically at age 25 – and his great love and muse.', 4.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s117', 'Dhanak', 'MOVIE', 'Nagesh Kukunoor', 'Krrish Chhabria, Hetal Gada, Vipin Sharma, Gulfam Khan, Suresh Menon, Vijay Maurya, Rajiv Lakshman, Ninad Kamat', 'India', 2015, 'TV-PG', 114, 'A movie-loving 10-year-old and her blind little brother trek to meet Indian superstar Shah Rukh Khan for help in getting the boy an eye operation.', 4.4);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s118', 'Final Account', 'MOVIE', 'Luke Holland', 'Various Artists', 'United Kingdom, United States', 2021, 'PG-13', 94, 'This documentary stitches together never-before-seen interviews with the last living generation of people who participated in Hitler''s Third Reich.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s119', 'Gurgaon', 'MOVIE', 'Shanker Raman', 'Akshay Oberoi, Pankaj Tripathi, Ragini Khanna, Aamir Bashir, Shalini Vatsa, Ashish Verma', 'India', 2017, 'TV-14', 106, 'When the daughter of a wealthy family returns from college, she gets a frosty welcome from her brother, who has problems – and plans – of his own.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s120', 'Here and There', 'MOVIE', 'JP Habac', 'Janine Gutierrez, JC Santos, Victor Anastacio, Yesh Burce, Lotlot De Leon', 'International', 2020, 'TV-MA', 99, 'After meeting through a heated exchange on social media, two people with different backgrounds begin an online romance in the midst of a pandemic.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s121', 'Heroes of Goo Jit Zu', 'SERIES', 'Unknown', 'Jon Allen, Kellen Goff, Joe Hernandez, Kaiji Tang', 'Australia', 2021, 'TV-Y7', 180, 'After a meteor crash, a group of zoo animals transforms into squishy, gooey and stretchy superheroes with special powers and soon takes on evildoers.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s122', 'Hotel Del Luna', 'SERIES', 'Unknown', 'Lee Ji-eun, Yeo Jin-goo, Shin Jung-geun, Seo Yi-sook, Bae Hae-sun, Pyo Ji-hoon, Cho Hyun-chul, Kang Hong-suk, Lee Do-hyun, Lee Tae-seon, Kang Mina, Park You-na, Oh Ji-ho', 'International', 2019, 'TV-14', 72, 'When he''s invited to manage a hotel for dead souls, an elite hotelier gets to know the establishment''s ancient owner and her strange world.', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s123', 'In the Cut', 'MOVIE', 'Jane Campion', 'Meg Ryan, Mark Ruffalo, Jennifer Jason Leigh, Nick Damici, Sharrieff Pugh, Kevin Bacon, Yaani King Mondschein, Heather Litteer', 'United Kingdom, Australia, France, United States', 2003, 'R', 118, 'After embarking on an affair with the cop probing the murder of a young woman, an insular schoolteacher suspects her lover was involved in the crime.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s124', 'Luv Kushh', 'SERIES', 'Unknown', 'Various Artists', 'International', 2012, 'TV-Y7', 72, 'Based on the last book of the epic Ramayana, this series follows the endeavors and adventures of Lord Rama’s twin sons through their childhood.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s125', 'Pororo - The Little Penguin', 'SERIES', 'Unknown', 'Various Artists', 'South Korea', 2013, 'TV-Y7', 111, 'On a tiny island, Pororo the penguin has fun adventures with his friends Eddy the fox, Loopy the beaver, Poby the polar bear and Crong the dinosaur.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s126', 'Q-Force', 'SERIES', 'Unknown', 'Sean Hayes, Wanda Sykes, Laurie Metcalf, David Harbour, Gary Cole, Patti Harrison, Matt Rogers', 'United States', 2021, 'TV-MA', 99, 'A gay superspy and his scrappy LGBTQ squad fight to prove themselves to the agency that underestimated them. Today, West Hollywood… tomorrow, the world!', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s127', 'Shikara', 'MOVIE', 'Vidhu Vinod Chopra', 'Aadil Khan, Sadia Khateeb, Zain Khan Durrani, Priyanshu Chatterjee, Bhavna Chauhan, Ashwin Dhar, Farid Azad Khan, Saghar Sehrai', 'India', 2020, 'TV-14', 115, 'A couple must strive to remain resilient after regional hostilities drive them from their beloved home into a refugee camp.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s128', 'A Cinderella Story', 'MOVIE', 'Mark Rosman', 'Hilary Duff, Chad Michael Murray, Jennifer Coolidge, Dan Byrd, Regina King, Julie Gonzalo, Lin Shaye, Madeline Zima, Andrea Avery, Mary Pat Gleason, Paul Rodriguez, Whip Hubley, Kevin Kilner, Erica Hu', 'United States, Canada', 2004, 'PG', 95, 'Teen Sam meets the boy of her dreams at a dance before returning to toil in her stepmother''s diner. Can her lost cell phone bring them together?', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s129', 'Agatha Christie''s Crooked House', 'MOVIE', 'Gilles Paquet-Brenner', 'Glenn Close, Terence Stamp, Max Irons, Gillian Anderson, Christina Hendricks, Stefanie Martini, Julian Sands, Honor Kneafsey, Christian McKay, Amanda Abbington', 'International', 2017, 'PG-13', 115, 'When a detective investigates the death of his ex-lover''s grandfather, he uncovers secrets about the tycoon''s manipulative family.', 4.4);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s130', 'An Unfinished Life', 'MOVIE', 'Lasse Hallström', 'Robert Redford, Jennifer Lopez, Morgan Freeman, Josh Lucas, Damian Lewis, Camryn Manheim, Becca Gardner, Lynda Boyd, Rob Hayter, P. Lynn Johnson', 'Germany, United States', 2005, 'PG-13', 108, 'A grieving widow and her daughter move in with her estranged father-in-law in Wyoming, where time allows them to heal and forgive.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s131', 'Barbie Big City Big Dreams', 'MOVIE', 'Scott Pleydell-Pearce', 'America Young, Amber May, Giselle Fernandez, Alejandro Saab, Dinora Walcott', 'International', 2021, 'TV-Y', 63, 'At a summer performing arts program in New York City, Barbie from Malibu meets Barbie from Brooklyn, and the two become fast friends.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s132', 'Blade Runner: The Final Cut', 'MOVIE', 'Ridley Scott', 'Harrison Ford, Rutger Hauer, Sean Young, Edward James Olmos, M. Emmet Walsh, Daryl Hannah, William Sanderson, Brion James, Joe Turkel, Joanna Cassidy, James Hong, Morgan Paull', 'United States', 1982, 'R', 117, 'In a smog-choked dystopian Los Angeles, blade runner Rick Deckard is called out of retirement to snuff a quartet of escaped "replicants."', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s133', 'Brave Animated Series', 'SERIES', 'Unknown', 'Tseng Yun-fan, Kao Yun-shuo, Chiang Ching-yen, Meng Ching-fu, Huang Bai-wei, Ma Kuo-yao, Chen Yen-chun, Sun Ke-fang, Kai Yang-niu, Chen Yu-wen, Nick Liao, Lin Kai-ling, Mickey Huang, Liu Kuan-ting, Ji', 'International', 2021, 'TV-MA', 78, 'A group of superheroes sets out to rid the world of evil — only to realize they may not be standing on the side of justice. Based on a popular comic.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s134', 'Chappie', 'MOVIE', 'Neill Blomkamp', 'Sharlto Copley, Hugh Jackman, Sigourney Weaver, Dev Patel, Ninja, Yo-Landi Visser, Jose Pablo Cantillo, Brandon Auret, Johnny Selema, Maurice Carpede', 'South Africa, United States', 2015, 'R', 121, 'In a futuristic society where an indestructible robot police force keeps crime at bay, a lone droid evolves to the next level of artificial intelligence.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s135', 'Clear and Present Danger', 'MOVIE', 'Phillip Noyce', 'Harrison Ford, Willem Dafoe, Anne Archer, Joaquim de Almeida, Henry Czerny, Harris Yulin, Donald Moffat, Miguel Sandoval, Benjamin Bratt, Dean Jones, Thora Birch, James Earl Jones, Raymond Cruz', 'United States, Mexico', 1994, 'PG-13', 142, 'When the president''s friend is murdered, CIA Deputy Director Jack Ryan becomes unwittingly involved in an illegal war against a Colombian drug cartel.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s136', 'Cliffhanger', 'MOVIE', 'Renny Harlin', 'Sylvester Stallone, John Lithgow, Michael Rooker, Janine Turner, Rex Linn, Caroline Goodall, Leon, Craig Fairbrass, Ralph Waite, Max Perlich, Paul Winfield', 'United States, Italy, France, Japan', 1993, 'R', 113, 'Ranger Gabe Walker and his partner are called to rescue a group of stranded climbers, only to learn the climbers are actually thieving hijackers.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s137', 'Cold Mountain', 'MOVIE', 'Anthony Minghella', 'Jude Law, Nicole Kidman, Renée Zellweger, Eileen Atkins, Brendan Gleeson, Philip Seymour Hoffman, Natalie Portman, Giovanni Ribisi, Donald Sutherland, Ray Winstone', 'United States, Italy, Romania, United Kingdom', 2003, 'R', 154, 'This drama follows a wounded Civil War soldier making the long journey home, while his faraway love fights for survival on her deceased father''s farm.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s138', 'Crocodile Dundee in Los Angeles', 'MOVIE', 'Simon Wincer', 'Paul Hogan, Linda Kozlowski, Jere Burns, Jonathan Banks, Aida Turturro, Alec Wilson, Gerry Skilton, Steve Rackman, Serge Cockburn, Paul Rodriguez, Mark Adair-Rios, Tiriel Mora, Grant Piro, Mike Tyson', 'Australia, United States', 2001, 'PG', 95, 'When Mick "Crocodile" Dundee and his family land in Los Angeles, they soon learn some lessons about American life in this comedy sequel.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s139', 'Dear John', 'MOVIE', 'Lasse Hallström', 'Channing Tatum, Amanda Seyfried, Richard Jenkins, Henry Thomas, D.J. Cotrona, Cullen Moss, Gavin McCulley, Jose Lucena Jr., Keith Robinson, Scott Porter', 'United States', 2010, 'PG-13', 108, 'While on summer leave, a U.S. soldier falls for a college student. But when he''s forced to reenlist, their handwritten letters hold the lovers together.', 5.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s140', 'Do the Right Thing', 'MOVIE', 'Spike Lee', 'Danny Aiello, Ossie Davis, Ruby Dee, Richard Edson, Giancarlo Esposito, Spike Lee, Bill Nunn, John Turturro, Paul Benjamin, Frankie Faison, Samuel L. Jackson, Rosie Perez, Martin Lawrence, Miguel Sand', 'United States', 1989, 'R', 120, 'On a sweltering day in Brooklyn, simmering racial tensions between residents rise to the surface and ignite rage, violence and tragedy.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s141', 'El patrón, radiografía de un crimen', 'MOVIE', 'Sebastián Schindel', 'Joaquín Furriel, Luis Ziembrowski, Guillermo Pfening, Mónica Lairana, Germán de Silva, Victoria Raposo, Andrea Garrote', 'Argentina, Venezuela', 2014, 'TV-MA', 100, 'A lawyer defends an illiterate man whose exploitation by a cruel boss while working as a butcher in Buenos Aires led to tragedy. Based on a true case.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s142', 'Extraction', 'MOVIE', 'Steven C. Miller', 'Bruce Willis, Kellan Lutz, Gina Carano, D.B. Sweeney, Joshua Mikel, Steve Coulter, Dan Bilzerian, Heather Johansen', 'United States, United Kingdom, Canada', 2015, 'R', 82, 'When a retired CIA agent is kidnapped, his son, a government analyst, embarks on an unauthorized mission to find him and halt a terrorist plot.', 4.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s143', 'Freedom Writers', 'MOVIE', 'Richard LaGravenese', 'Hilary Swank, Patrick Dempsey, Scott Glenn, Imelda Staunton, April L. Hernandez, Mario, Kristin Herrera, Jaclyn Ngan, Sergio Montalvo, Jason Finn, Deance Wyatt, Vanetta Smith', 'Germany, United States', 2007, 'PG-13', 124, 'While her at-risk students are reading classics such as "The Diary of Anne Frank," a teacher asks them to keep journals about their troubled lives.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s144', 'Green Lantern', 'MOVIE', 'Martin Campbell', 'Ryan Reynolds, Blake Lively, Peter Sarsgaard, Mark Strong, Tim Robbins, Jay O. Sanders, Taika Waititi, Angela Bassett', 'United States', 2011, 'PG-13', 114, 'Test pilot Hal Jordan harnesses glowing new powers for good when he wears an otherworldly ring and helps an intergalactic force stop a powerful threat.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s145', 'House Party', 'MOVIE', 'Reginald Hudlin', 'Christopher Reid, Christopher Martin, Robin Harris, Tisha Campbell, A.J. Johnson, Martin Lawrence, Paul Anthony, Bowlegged Lou, B-Fine, Edith Fields, Kelly Jo Minter, Clifton Powell, Verda Bridges', 'United States', 1990, 'R', 104, 'Grounded by his strict father, Kid risks life and limb to go to his best friend Play''s big bash but experiences one obstacle after another.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s146', 'House Party 2', 'MOVIE', 'George Jackson, Doug McHenry', 'Christopher Reid, Christopher Martin, Martin Lawrence, Bowlegged Lou, Paul Anthony, B-Fine, Tisha Campbell, Kamron, Iman, Queen Latifah', 'United States', 1991, 'R', 94, 'Kid goes off to college with scholarship money but when Play loses Kid''s tuition funds to a shady music promoter, they devise a wild plan to raise cash.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s147', 'House Party 3', 'MOVIE', 'Eric Meza', 'Christopher Reid, Christopher Martin, Tisha Campbell, David Edwards, Angela Means, Ketty Lester, Bernie Mac, Michael Colyar, Chris Tucker, Khandi Alexander', 'United States', 1994, 'R', 94, 'After Kid gets engaged, Play plans to throw the biggest bachelor party ever. But every celebration for these two always comes with complications.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s148', 'How to Be a Cowboy', 'SERIES', 'Unknown', 'Various Artists', 'International', 2021, 'TV-PG', 111, 'Dale Brisby uses social media savvy and rodeo skills to keep cowboy traditions alive — and now he''s teaching the world how to cowboy right, ol'' son.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s149', 'HQ Barbers', 'SERIES', 'Gerhard Mostert', 'Hakeem Kae-Kazim, Chioma Omeruah, Orukotan Adejola, Flora Chiedo, Emeka Nwagbaraocha, Anthony Oseyemi, Oluwabukola Thomas, Soibifaa Dokubo', 'International', 2020, 'TV-14', 72, 'When a family run barber shop in the heart of Lagos is threatened by real estate developers, they''ll do whatever it takes to stay in business.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s150', 'I Got the Hook Up', 'MOVIE', 'Michael Martin', 'Master P, Anthony Johnson, Gretchen Palmer, Frantz Turner, Richard Keats, Joe Estevez, William Knight, Anthony Boswell, Tommy ''Tiny'' Lister, Helen Martin, John Witherspoon, Mia X', 'United States', 1998, 'R', 93, 'After getting their hands on a misdirected shipment of cell phones, two hustlers try to cash in by hawking the merchandise from the back of their van.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s151', 'In Too Deep', 'MOVIE', 'Michael Rymer', 'Omar Epps, LL Cool J, Nia Long, Stanley Tucci, Pam Grier, Hill Harper, Jake Weber, David Patrick Kelly, Veronica Webb, Ron Canada, Robert LaSardo, Gano Grills, Ivonne Coll, Don Harvey, Mya, Nasir ''Na', 'United States', 1999, 'R', 97, 'Rookie cop Jeffrey Cole poses as a drug dealer to take down a crime lord and soon gets caught up in an underworld of bribery, intimidation and murder.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s152', 'Initial D', 'MOVIE', 'Andrew Lau Wai-keung, Alan Mak', 'Jay Chou, Anne Suzuki, Edison Chen, Anthony Wong Chau-sang, Shawn Yue, Chapman To, Jordan Chan, Kenny Bee', 'China, Hong Kong', 2005, 'TV-14', 109, 'By day, an 18-year-old delivers tofu for his father, a retired race car driver; but by night, it''s the teen''s turn to take the wheel.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s153', 'Janoskians: Untold and Untrue', 'MOVIE', 'Brett Weiner', 'Jai Brooks, Luke Brooks, James Yammouni, Daniel Sahyounie, Beau Brooks', 'United States', 2016, 'TV-MA', 88, 'Follow the story of three Australian brothers and their two friends who became an international sensation by posting pranks and gags on YouTube.', 5.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s154', 'Kid-E-Cats', 'SERIES', 'Unknown', 'Lori Gardner, Kate Bristol, Billy Bob Thompson, Marc Thompson, Erica Schroeder', 'Russia', 2016, 'TV-Y', 60, 'Cookie, Pudding and Candy are kitten siblings whose favorite things are sweet treats and letting their curiosity lead them on adventures in learning.', 5.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s155', 'Kuroko''s Basketball', 'SERIES', 'Unknown', 'Kensho Ono, Yuki Ono, Chiwa Saito, Yoshimasa Hosoya, Hirofumi Nojima, Kenji Hamada, Takuya Eguchi, Soichiro Hoshi, Tatsuhisa Suzuki, Go Inoue, Daisuke Ono, Ryohei Kimura, Junichi Suwabe, Kazuya Nakai,', 'Japan', 2015, 'TV-MA', 105, 'Five middle school basketball stars went to separate high schools, and now Tetsuya Kuroko and Seirin High are making their play for glory.', 3.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s156', 'Labyrinth', 'MOVIE', 'Jim Henson', 'David Bowie, Jennifer Connelly, Frank Oz, Kevin Clash, Anthony Asbury, Dave Goelz, Brian Henson, Ron Mueck, Karen Prell, Shari Weiser', 'United Kingdom, United States', 1986, 'PG', 101, 'In Jim Henson''s fantasy, teen Sarah embarks on a life-altering quest to rescue her little brother from the clutches of a treacherous goblin.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s157', 'Letters to Juliet', 'MOVIE', 'Gary Winick', 'Amanda Seyfried, Christopher Egan, Gael García Bernal, Vanessa Redgrave, Franco Nero, Luisa Ranieri, Marina Massironi, Milena Vukotic, Marcia DeBonis, Luisa De Santis, Lidia Biondi, Giordano Formenti,', 'United States', 2010, 'PG', 105, 'By responding to a letter addressed to Shakespeare''s tragic heroine Juliet Capulet, an American woman in Verona, Italy, is led in search of romance.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s158', 'Level 16', 'MOVIE', 'Danishka Esterhazy', 'Katie Douglas, Celina Martin, Peter Outerbridge, Sara Canning, Alexis Whelan, Amalia Williamson, Josette Halpert, Kiana Madeira', 'Canada', 2018, 'TV-14', 102, 'In a bleak academy that teaches girls the virtues of passivity, two students uncover the ghastly purpose behind their training and resolve to escape.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s159', 'Love Don''t Cost a Thing', 'MOVIE', 'Troy Byer', 'Nick Cannon, Christina Milian, Kenan Thompson, Kal Penn, Steve Harvey, Al Thompson, Ashley Monique Clark, Elimu Nelson, Nichole Robinson, Melissa Schuman', 'United States', 2003, 'PG-13', 101, 'A nerdy teen tries to make himself cool by association when he convinces a popular cheerleader to pose as his girlfriend.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s160', 'Love in a Puff', 'MOVIE', 'Pang Ho-cheung', 'Miriam Chin Wah Yeung, Shawn Yue, Singh Hartihan Bitto, Isabel Chan, Cheung Tat-ming, Matt Chow, Chui Tien-you, Queenie Chu, Charmaine Fong, Vincent Kok', 'Hong Kong', 2010, 'TV-MA', 103, 'When the Hong Kong government enacts a ban on smoking cigarettes indoors, the new law drives hard-core smokers outside, facilitating unlikely connections.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s161', 'Major Dad', 'SERIES', 'Unknown', 'Gerald McRaney, Shanna Reed, Nicole Dubuc, Chelsea Hertford, Marisa Ryan, Matt Mulhern, Beverly Archer, Jon Cypher', 'United States', 1992, 'TV-PG', 132, 'When he marries a journalist and becomes stepdad to her daughters, a U.S. Marine finds his once-orderly life no longer entirely under his command.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s162', 'Mars Attacks!', 'MOVIE', 'Tim Burton', 'Jack Nicholson, Glenn Close, Annette Bening, Pierce Brosnan, Danny DeVito, Martin Short, Sarah Jessica Parker, Michael J. Fox, Rod Steiger, Tom Jones, Lukas Haas, Natalie Portman', 'United States', 1996, 'PG-13', 106, 'As flying saucers head for Earth, the president of the United States prepares to welcome alien visitors but soon learns they''re not coming in peace.', 4.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s163', 'Marshall', 'MOVIE', 'Reginald Hudlin', 'Chadwick Boseman, Josh Gad, Kate Hudson, Sterling K. Brown, Dan Stevens, James Cromwell, Keesha Sharp, Roger Guenveur Smith, Derrick Baskin, Barrett Doss', 'United States, China, Hong Kong', 2017, 'PG-13', 118, 'This biopic of Thurgood Marshall, the first Black U.S. Supreme Court justice, centers on his pivotal work in a sensational case as an NAACP lawyer.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s164', 'My Boss''s Daughter', 'MOVIE', 'David Zucker', 'Ashton Kutcher, Tara Reid, Jeffrey Tambor, Andy Richter, Michael Madsen, Jon Abrahams, David Koechner, Carmen Electra, Kenan Thompson, Terence Stamp, Molly Shannon', 'United States', 2003, 'R', 86, 'A young man house-sits for his mean boss, hoping to use it as an opportunity to win the heart of the boss''s daughter, on whom he''s long had a crush.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s165', 'Mystery Men', 'MOVIE', 'Kinka Usher', 'Ben Stiller, Hank Azaria, William H. Macy, Janeane Garofalo, Kel Mitchell, Paul Reubens, Wes Studi, Greg Kinnear, Geoffrey Rush, Lena Olin, Eddie Izzard, Artie Lange, Pras, Claire Forlani, Tom Waits', 'United States', 1999, 'PG-13', 121, 'A team of far-from-super heroes try to earn respect by springing into action when brave and dashing Captain Amazing disappears.', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s166', 'Oldsters', 'SERIES', 'Unknown', 'Patricio Contreras, Alejandro Goic, Sergio Hernández, Mariana Loyola Ruz, Alejandro Trejo, Daniel Alcaíno Cuevas, Nicolás Poblete, Susana Hidalgo, Gloria Münchmeyer', 'International', 2019, 'TV-MA', 165, 'Three friends in their 70s step out of retirement to become a band of outlaws whose mission is to help those let down by the justice system.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s167', 'Once Upon a Time in America', 'MOVIE', 'Sergio Leone', 'Robert De Niro, James Woods, Elizabeth McGovern, Treat Williams, Tuesday Weld, Burt Young, Joe Pesci, Danny Aiello, William Forsythe, James Hayden', 'Italy, United States', 1984, 'R', 229, 'Director Sergio Leone''s sprawling crime epic follows a group of Jewish mobsters who rise in the ranks of organized crime in 1920s New York City.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s168', 'Open Season 2', 'MOVIE', 'Matthew O''Callaghan, Todd Wilderman', 'Joel McHale, Mike Epps, Jane Krakowski, Billy Connolly, Crispin Glover, Steve Schirripa, Georgia Engel, Diedrich Bader, Cody Cameron, Fred Stoller, Olivia Hack', 'United States, Canada', 2008, 'PG', 76, 'Elliot the buck and his forest-dwelling cohorts must rescue their dachshund pal from some spoiled pets bent on returning him to domesticity.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s169', 'Osmosis Jones', 'MOVIE', 'Bobby Farrelly, Peter Farrelly', 'Chris Rock, Laurence Fishburne, David Hyde Pierce, Brandy Norwood, William Shatner, Ron Howard, Kid Rock, Ben Stein', 'United States', 2001, 'PG', 95, 'Peter and Bobby Farrelly outdo themselves with this partially animated tale about an out-of-shape 40-year-old man who''s the host to various organisms.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s170', 'Poseidon', 'MOVIE', 'Wolfgang Petersen', 'Josh Lucas, Kurt Russell, Jacinda Barrett, Richard Dreyfuss, Emmy Rossum, Mía Maestro, Mike Vogel, Kevin Dillon, Freddy Rodríguez', 'United States', 2006, 'PG-13', 98, 'A tidal wave spells disaster for a ship of New Year''s Eve revelers when it capsizes the mammoth vessel, sending passengers into a battle for survival.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s171', 'Rhyme & Reason', 'MOVIE', 'Peter Spirer', 'Too $hort, B-Real, Kurtis Blow, Da Brat, Grandmaster Caz, Sean "P. Diddy" Combs, Chuck D., Desiree Densiti, Dr. Dre, E-40, MC Eiht, Heavy D, Lauryn Hill, Ice-T, Wyclef Jean, Ras Kass, KRS-One, L.V., M', 'United States', 1997, 'R', 89, 'The world and culture of rap song topics such as race, violence, police, family and sex are examined by hip-hop performers from both coasts.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s172', 'Same Kind of Different as Me', 'MOVIE', 'Michael Carney', 'Greg Kinnear, Renée Zellweger, Djimon Hounsou, Jon Voight, Olivia Holt', 'United States', 2017, 'PG-13', 120, 'A wealthy couple whose marriage is on the rocks befriends a local homeless man who changes their perspectives in this inspiring true story.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s173', 'School of Rock', 'MOVIE', 'Richard Linklater', 'Jack Black, Joan Cusack, Mike White, Sarah Silverman, Lee Wilkof, Kate McGregor-Stewart, Adam Pascal, Suzzanne Douglas, Miranda Cosgrove, Kevin Alexander Clark, Joey Gaydos Jr., Robert Tsai, Veronica ', 'United States, Germany', 2003, 'PG-13', 110, 'Musician Dewey Finn gets a job as a fourth-grade substitute teacher, where he secretly begins teaching his students the finer points of rock ''n'' roll.', 4.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s174', 'Snervous Tyler Oakley', 'MOVIE', 'Amy Rice', 'Tyler Oakley', 'United States', 2015, 'PG-13', 83, 'The inspiring Internet star and LGBT advocate shares an intimate view of his life and relationships during his international "Slumber Party" tour.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s175', 'Tears of the Sun', 'MOVIE', 'Antoine Fuqua', 'Bruce Willis, Monica Bellucci, Cole Hauser, Eamonn Walker, Johnny Messner, Nick Chinlund, Charles Ingram, Paul Francis, Chad Smith, Tom Skerritt, Malick Bowens, Awaovieyi Agie', 'United States', 2003, 'R', 121, 'A Navy SEAL is sent to a war-torn African jungle to rescue a doctor, only to realize he must also save the refugees in the physician''s care.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s176', 'The Blue Lagoon', 'MOVIE', 'Randal Kleiser', 'Brooke Shields, Christopher Atkins, Leo McKern, William Daniels, Elva Josephson, Glenn Kohan, Alan Hopgood, Gus Mercurio', 'United States', 1980, 'R', 105, 'Two shipwrecked children, stranded for years on a deserted island, fall in love as teenagers and attempt to forge a life in the isolated paradise.', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s177', 'The Golden Child', 'MOVIE', 'Michael Ritchie', 'Eddie Murphy, J.L. Reate, Charles Dance, Charlotte Lewis, Victor Wong, Randall Tex Cobb, James Hong, Shakti Chen, Tau Logo, Tiger Chung Lee', 'United States', 1986, 'PG-13', 94, 'A fast-talking L.A. social worker goes through a series of traps and terrors to find a kidnapped Tibetan child with mystical powers.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s178', 'The Guns of Navarone', 'MOVIE', 'J. Lee Thompson', 'Gregory Peck, David Niven, Anthony Quinn, Stanley Baker, Anthony Quayle, James Darren, Irene Papas, Gia Scala, James Robertson Justice, Richard Harris', 'United Kingdom, United States', 1961, 'TV-14', 156, 'During World War II, British forces launch an attack designed to take out the massive Nazi cannons that guard a critical sea channel.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s179', 'The Interview', 'MOVIE', 'Evan Goldberg, Seth Rogen', 'James Franco, Seth Rogen, Lizzy Caplan, Randall Park, Diana Bang, Timothy Simons, Reese Alexander, James Yi', 'United States', 2014, 'R', 112, 'Seth Rogen and James Franco star in this provocative comedy about two journalists recruited by the CIA after they arrange an interview with Kim Jong-un.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s180', 'The Nutty Professor', 'MOVIE', 'Tom Shadyac', 'Eddie Murphy, Jada Pinkett Smith, James Coburn, Larry Miller, Dave Chappelle, John Ales, Patricia Wilson, Jamal Mixon', 'United States', 1996, 'PG-13', 95, 'After being made fun of for his weight, a kind and brainy professor takes a dose of a revolutionary formula that changes more than just his appearance.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s181', 'The Nutty Professor II: The Klumps', 'MOVIE', 'Peter Segal', 'Eddie Murphy, Janet Jackson, Larry Miller, John Ales, Richard Gant, Anna Maria Horsford, Melinda McGraw, Jamal Mixon, Gabriel Williams, Chris Elliott', 'International', 2000, 'PG-13', 107, 'After getting engaged, Sherman Klump prepares for his big day. But his sinister alter ego Buddy Love threatens to ruin his wedding and reputation.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s182', 'Turning Point: 9/11 and the War on Terror', 'SERIES', 'Unknown', 'Various Artists', 'International', 2021, 'TV-14', 72, 'This unflinching series documents the 9/11 terrorist attacks, from Al Qaeda''s roots in the 1980s to America''s response, both at home and abroad.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s183', 'Welcome Home Roscoe Jenkins', 'MOVIE', 'Malcolm D. Lee', 'Martin Lawrence, James Earl Jones, Joy Bryant, Margaret Avery, Mike Epps, Mo''Nique, Cedric the Entertainer, Nicole Ari Parker, Michael Clarke Duncan, Louis C.K.', 'United States', 2008, 'PG-13', 114, 'R.J. travels to Georgia for his parents'' 50th anniversary. But after pompously flaunting his Hollywood lifestyle, he must examine what he''s become.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s184', 'In the Line of Fire', 'MOVIE', 'Wolfgang Petersen', 'Clint Eastwood, John Malkovich, Rene Russo, Dylan McDermott, Gary Cole, Fred Thompson, John Mahoney, Gregory Alan Williams, Jim Curley, Sally Hughes', 'United States', 1993, 'R', 129, 'A twisted yet ingenious killer torments a veteran Secret Service agent who''s haunted by his failure years ago to save President John F. Kennedy.', 3.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s185', 'Sparking Joy', 'SERIES', 'Unknown', 'Marie Kondo', 'United States', 2021, 'TV-PG', 168, 'In this reality series, Marie Kondo brings her joyful tidying tactics to people struggling to balance work and home life — and shares her own world.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s186', 'Untold: Crime & Penalties', 'MOVIE', 'Chapman Way, Maclain Way', 'Various Artists', 'International', 2021, 'TV-MA', 86, 'They were the bad boys of hockey — a team bought by a man with mob ties, run by his 17-year-old son, and with a rep for being as violent as they were good.', 4.4);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s187', 'Hometown Cha-Cha-Cha', 'SERIES', 'Unknown', 'Shin Min-a, Kim Seon-ho, Lee Sang-yi, Gong Min-jeung, Kim Young-ok, Cho Han-cheul, In Gyo-jin, Lee Bong-ryeon, Cha Cheong-hwa, Kang Hyung-suk', 'International', 2021, 'TV-14', 177, 'A big-city dentist opens up a practice in a close-knit seaside village, home to a charming jack-of-all-trades who is her polar opposite in every way.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s188', 'The Ingenuity of the Househusband', 'SERIES', 'Unknown', 'Kenjiro Tsuda', 'International', 2021, 'TV-G', 171, 'A tough guy with a knack for housework tackles household tasks with meticulous care in these comedic live-action vignettes.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s189', '2 Alone in Paris', 'MOVIE', 'Ramzy Bedia, Éric Judor', 'Ramzy Bedia, Éric Judor, Benoît Magimel, Kristin Scott Thomas, Élodie Bouchez, Édouard Baer, Fred Testot, Omar Sy', 'France', 2008, 'TV-MA', 97, 'A bumbling Paris policeman is doggedly determined to capture the master thief that repeatedly eludes him, even when they''re the last two men on Earth.', 4.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s190', 'Bread Barbershop', 'SERIES', 'Unknown', 'Um Sang-hyun, Park Yoon-hee, Kang Shi-hyun, Hong Bum-ki, Kim Hyun-wook, Lee In-suk, Song Ha-rim', 'International', 2020, 'TV-Y', 108, 'In a town filled with food, Bread is a master cake decorator who gives life-changing makeovers that will put any customer in an amazing mood.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s191', 'Thimmarusu', 'MOVIE', 'Sharan Koppisetty', 'Satya Dev, Priyanka Jawalkar, Brahmaji', 'India', 2021, 'TV-14', 125, 'Eight years after a young man is framed for murder, an up-and-coming lawyer re-opens the case, beginning a tricky mission to find the real culprit.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s192', 'Wind River', 'MOVIE', 'Taylor Sheridan', 'Jeremy Renner, Elizabeth Olsen, Jon Bernthal, Gil Birmingham, Kelsey Asbille, Tantoo Cardinal, Teo Briones, Matthew Del Negro, Hugh Dillon, Julia Jones, James Jordan, Eric Lange, Martin Sensmeier, Mas', 'United Kingdom, Canada, United States', 2017, 'R', 107, 'A tracker with the U.S. Fish and Wildlife Service assists a rookie FBI agent who''s investigating a teen girl''s murder on a remote Wyoming reservation.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s193', 'C Kkompany', 'MOVIE', 'Sachin Yardi', 'Mithun Chakraborty, Tusshar Kapoor, Anupam Kher, Rajpal Yadav, Raima Sen, Dilip Prabhavalkar, Sanjay Mishra', 'India', 2008, 'TV-14', 127, 'Three broke friends pose as an underworld gang for extortion, but their plan takes on a life of its own when their phony company becomes famous.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s194', 'D.P.', 'SERIES', 'Unknown', 'Jung Hae-in, Koo Kyo-hwan, Kim Sung-kyun, Son Suk-ku', ', South Korea', 2021, 'TV-MA', 117, 'A young private’s assignment to capture army deserters reveals the painful reality endured by each enlistee during his compulsory call of duty.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s195', 'Deadly Sins', 'SERIES', 'Unknown', 'Frank Ramirez, Patricia Castañeda, Chela del Río, Patrick Delmas, María José Martínez, Robinson Díaz, Juan Ángel, Guillermo Olarte, Constanza Duque, Marcela Carvajal', 'International', 2002, 'TV-MA', 72, 'A multimillionaire fakes his death and forces his relatives to live together in his mansion for one year to see who''s worthy of inheriting his fortune.', 3.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s196', 'EMI: Liya Hai To Chukana Padega', 'MOVIE', 'Saurabh Kabra', 'Sanjay Dutt, Arjun Rampal, Malaika Arora, Aashish Chaudhary, Neha Uberoi, Urmila Matondkar, Manoj Joshi, Daya Shankar Pandey, Pushkar Jog, Kulbhushan Kharbanda', 'India', 2008, 'TV-14', 128, 'A bank hires an enigmatic and unorthodox debt collector to recover money from four borrowers who are unable to pay their loans.', 4.4);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s197', 'He''s All That', 'MOVIE', 'Mark Waters', 'Addison Rae, Tanner Buchanan, Rachael Leigh Cook, Madison Pettis, Isabella Crovetti, Matthew Lillard, Peyton Meyer, Annie Jacob, Myra Molloy, Kourtney Kardashian', 'International', 2021, 'TV-14', 92, 'An influencer specializing in makeovers bets she can transform an unpopular classmate into prom king in this remake of the teen classic "She''s All That."', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s198', 'I Heart Arlo', 'SERIES', 'Unknown', 'Michael J. Woodard, Mary Lambert, Jonathan Van Ness, Haley Tju, Brett Gelman, Tony Hale, Vincent Rodriguez III, Annie Potts, Jessica Williams, Melissa Villaseñor, Cathy Vu, Jennifer Coolidge, Flea', 'International', 2021, 'TV-Y7', 78, 'It''s a whole new world for Arlo and his one-of-a kind pals when they set out to restore a run-down New York City neighborhood — and make it their own.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s199', 'King of Boys: The Return of the King', 'SERIES', 'Kemi Adetiba', 'Sola Sobowale, Toni Tones, Richard Mofe-Damijo, Efa Iwara, Titi Kuti, Tobechukwu "iLLbliss" Ejiofor, Remilekun "Reminisce" Safaru, Charles  "Charly Boy" Oputa, Nse Ikpe-Etim, Keppy Ekpenyong Bassey, B', 'Nigeria', 2021, 'TV-MA', 99, 'Alhaja Eniola Salami starts anew and sets her sights on a different position of power, fueled by revenge, regret and ruthlessness.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s200', 'Koi Aap Sa', 'MOVIE', 'Partho Mitra', 'Aftab Shivdasani, Natassha, Dipannita Sharma, Himanshu Mallik, Vaidya Advai, Pushy Anand, Shama Deshpande, Rajendra Gupta', 'India', 2006, 'TV-14', 135, 'Star athlete Rohan has his eye on a beautiful art student. But when his best friend Simran experiences a crisis, he drops everything to help her.', 3.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s201', 'Krishna Cottage', 'MOVIE', 'Santram Varma', 'Sohail Khan, Isha Koppikar, Natassha, Rati Agnihotri, Vrajesh Hirjee, Divya Palat, Hiten Tejwani, Rajendranath Zutshi', 'India', 2004, 'TV-14', 124, 'True love is put to the test when another woman comes between a pair of star-crossed young lovers in this thriller.', 4.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s202', 'Kucch To Hai', 'MOVIE', 'Anil V. Kumar, Anurag Basu', 'Tusshar Kapoor, Esha Deol, Natassha, Vrajesh Hirjee, Kusumit Sana, Rishi Kapoor, Moon Moon Sen, Johny Lever, Ashay Chitre, Jeetendra', 'India', 2003, 'TV-14', 136, 'A student tries to steal a test from a teacher''s home, leaving him for dead after an accident. A string of murders may be the professor''s revenge.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s203', 'Kyaa Kool Hai Hum', 'MOVIE', 'Sangeeth Sivan', 'Tusshar Kapoor, Riteish Deshmukh, Isha Koppikar, Neha Dhupia, Anupam Kher, Jay Sean', 'India', 2005, 'TV-MA', 165, 'Longtime friends Rahul and Karan head to Mumbai intent on making their dreams come true, but both men are suddenly saddled with bad luck.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s204', 'Kyaa Kool Hain Hum 3', 'MOVIE', 'Umesh Ghadge', 'Tusshar Kapoor, Aftab Shivdasani, Krishna Abhishek, Mandana Karimi, Shakti Kapoor, Darshan Jariwala, Sushmita Mukherjee, Meghna Naidu, Anand Kumar, Claudia Ciesla', 'India', 2016, 'TV-MA', 124, 'When an unlikely porn actor falls for a woman outside the industry, he employs his co-stars as a stand-in traditional family to impress her father.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s205', 'Kyaa Super Kool Hain Hum', 'MOVIE', 'Sachin Yardi', 'Tusshar Kapoor, Riteish Deshmukh, Anupam Kher, Rohit Shetty, Neha Sharma, Chunky Pandey, Sarah-Jane Dias, Razak Khan, Kavin Dave', 'India', 2012, 'TV-MA', 136, 'An aspiring actor and a struggling DJ team up to pursue the ladies they love and a diamond that rightfully belongs to their oversexed dog.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s206', 'Kyo Kii... Main Jhuth Nahin Bolta', 'MOVIE', 'David Dhawan', 'Govinda, Sushmita Sen, Rambha, Anupam Kher, Satish Kaushik, Sharad Kapoor, Kiran Kumar, Mohnish Bahl', 'India', 2001, 'TV-14', 150, 'The life and career of a lawyer are thrown into chaos when his son''s wish magically renders him incapable of telling a lie.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s207', 'LSD: Love, Sex Aur Dhokha', 'MOVIE', 'Dibakar Banerjee', 'Nushrat Bharucha, Anshuman Jha, Neha Chauhan, Rajkummar Rao, Arya Banerjee, Amit Sial, Herry Tangri', 'India', 2010, 'TV-MA', 112, 'This provocative drama examines how the voyeuristic nature of modern society affects three unusual couples in Northern India.', 4.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s208', 'Mission Istaanbul: Darr Ke Aagey Jeet Hai', 'MOVIE', 'Apoorva Lakhia', 'Vivek Oberoi, Zayed Khan, Shriya Saran, Nikitin Dheer, Shabbir Ahluwalia, Sunil Shetty, Shweta Bhardwaj', 'India', 2008, 'TV-14', 119, 'A television journalist makes a risky career move by accepting a job offer from a controversial Istanbul television station.', 5.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s209', 'Once Upon a Time in Mumbaai', 'MOVIE', 'Milan Luthria', 'Ajay Devgn, Emraan Hashmi, Kangana Ranaut, Prachi Desai, Randeep Hooda, Naved Aslam, Asif Basra, Avtar Gill', 'India', 2010, 'TV-14', 133, 'Mumbai''s top mob boss rules the underworld with honor and compassion, but his power-hungry protégé will shake up the world of organized crime.', 4.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s210', 'Once Upon a Time in Mumbai Dobaara!', 'MOVIE', 'Milan Luthria', 'Akshay Kumar, Imran Khan, Sonakshi Sinha, Sonali Bendre, Sarfaraz Khan, Mahesh Manjrekar, Abhimanyu Singh, Kurush Deboo, Pitobash, Chetan Hansraj', 'India', 2013, 'TV-14', 142, 'This turbulent sequel to Once Upon a Time in Mumbai carries on the saga of the gangland don Shoaib Khan, who continues pressing for more control.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s211', 'Ragini MMS', 'MOVIE', 'Pawan Kripalani', 'Kainaz Motivala, Rajkummar Rao, Rajat Kaul, Janice, Shernaza, Mangala Ahire, Vinod Rawat', 'India', 2011, 'TV-MA', 93, 'A couple out to have a sensuous weekend at a house outside of Mumbai finds it rigged with surveillance cameras and occupied by an evil entity.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s212', 'Ragini MMS 2', 'MOVIE', 'Bhushan Patel', 'Sunny Leone, Saahil Prem, Parvin Dabas, Sandhya Mridul, Divya Dutta, Soniya Mehra, Kainaz Motivala, Karan Mehra', 'India', 2014, 'TV-MA', 113, 'The horror continues when Ragini''s video goes viral and a sleazy director decides to make a movie about the incident in the original house.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s213', 'Rebellion', 'SERIES', 'Unknown', 'Charlie Murphy, Ruth Bradley, Sarah Greene, Brian Gleeson, Michelle Fairley, Ian McElhinney, Michael Ford-FitzGerald, Paul Reid, Barry Ward, Tom Turner, Perdita Weeks, Andrew Simpson, Sophie Robinson', 'Ireland', 2016, 'TV-MA', 78, 'As World War I rages, three women and their families in Dublin choose sides in the violent Easter Rising revolt against British rule.', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s214', 'RIDE ON TIME', 'SERIES', 'Unknown', 'King & Prince, Hey! Say! JUMP, KAT-TUN, NEWS, Kansai Johnny''s Jr., Snow Man, Tomoyuki Yara, Travis Japan, Bi shonen, SixTONES, HiHi Jets, Kis-My-Ft2, Koichi Domoto', 'International', 2021, 'TV-PG', 84, 'Take a deep dive into the beautiful world of Japan''s top male idol groups from number one producer Johnny''s in this revealing docuseries.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s215', 'SAS: Rise of the Black Swan', 'MOVIE', 'Magnus Martens', 'Sam Heughan, Ruby Rose, Andy Serkis, Hannah John-Kamen, Tom Wilkinson, Tom Hopper, Noel Clarke, Anne Reid, Owain Yeoman, Jing Lusi, Ray Panthaki, Richard McCabe, Douglas Reith', 'International', 2021, 'R', 124, 'A special forces operative traveling from London to Paris with his girlfriend takes action when armed, ruthless mercenaries seize control of their train.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s216', 'Shootout at Lokhandwala', 'MOVIE', 'Apoorva Lakhia', 'Amitabh Bachchan, Sanjay Dutt, Sunil Shetty, Arbaaz Khan, Abhishek Bachchan, Vivek Oberoi, Tusshar Kapoor, Rohit Roy, Shabbir Ahluwalia, Dia Mirza, Amrita Singh, Neha Dhupia', 'India', 2007, 'TV-MA', 116, 'Based on a true story, this action film follows an incident that stunned a nation in the early 1990s. In Mumbai, India, the notorious gangster Maya holds off veteran cop Khan and a force of more than 200 policemen in a six-hour bloody gunfight.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s217', 'Shor In the City', 'MOVIE', 'Raj Nidimoru, Krishna D.K.', 'Sendhil Ramamurthy, Tusshar Kapoor, Nikhil Dwivedi, Preeti Desai, Sundeep Kishan, Radhika Apte, Pitobash, Girija Oak, Alok Chaturvedi, Sudhir Chowdhary', 'India', 2011, 'TV-14', 106, 'When three small-time Mumbai crooks steal a bag on a train, they find that it''s filled with weapons and realize that their lives may be in danger.', 3.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s218', 'The Dirty Picture', 'MOVIE', 'Milan Luthria', 'Vidya Balan, Emraan Hashmi, Tusshar Kapoor, Naseeruddin Shah, Rajesh Sharma, Imran Hasnee, Anju Mahendru', 'India', 2011, 'TV-14', 145, 'After running away from home in search of movie stardom, a village girl rises to become a prominent sex symbol.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s219', 'Titletown High', 'SERIES', 'Unknown', 'Various Artists', 'International', 2021, 'TV-14', 99, 'In a Georgia town where football rules and winning is paramount, a high school team tackles romance, rivalries and real life while vying for a title.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s220', 'EDENS ZERO', 'SERIES', 'Unknown', 'Takuma Terashima, Mikako Komatsu, Rie Kugimiya, Hiromichi Tezuka, Shiori Izawa, Shiki Aoki, Sayaka Ohara, Hochu Otsuka, Kikuko Inoue', 'Japan', 2021, 'TV-14', 99, 'Aboard the Edens Zero, a lonely boy with the ability to control gravity embarks on an adventure to meet the fabled space goddess known as Mother.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s221', 'Family Reunion', 'SERIES', 'Unknown', 'Loretta Devine, Tia Mowry-Hardrict, Anthony Alabi, Talia Jackson, Isaiah Russell-Bailey, Cameron J. Wright, Jordyn Raya James, Richard Roundtree', 'United States', 2021, 'TV-PG', 108, 'When the McKellan family moves from Seattle to small-town Georgia, life down South – and traditional grandparents – challenge their big-city ways.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s222', 'Bob Ross: Happy Accidents, Betrayal & Greed', 'MOVIE', 'Joshua Rofé', 'Bob Ross', 'International', 2021, 'TV-14', 93, 'Bob Ross brought joy to millions as the world’s most famous art instructor. But a battle for his business empire cast a shadow over his happy trees.', 3.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s223', 'Clickbait', 'SERIES', 'Brad Anderson', 'Zoe Kazan, Betty Gabriel, Adrian Grenier, Phoenix Raei, Abraham Lim, Jessica Collins, Camaron Engels, Jaylin Fletcher, Liz Alexander, Joyce Guy, Daniel Henshall, Ian Meadows, Jamie Timony, Steve Mouza', 'International', 2021, 'TV-MA', 69, 'When family man Nick Brewer is abducted in a crime with a sinister online twist, those closest to him race to uncover who is behind it and why.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s224', 'John of God: The Crimes of a Spiritual Healer', 'SERIES', 'Mauricio Dias, Tatiana Villela', 'Various Artists', 'International', 2021, 'TV-MA', 141, 'Idolized medium João Teixeira de Faria rises to international fame before horrifying abuse is revealed by survivors, prosecutors and the press.', 4.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s225', 'Motel Makeover', 'SERIES', 'Unknown', 'Various Artists', 'International', 2021, 'TV-14', 66, 'Amid project pitfalls and a pandemic, besties-turned-business partners bring their design magic to a rundown motel and revamp it into a go-to getaway.', 3.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s226', 'Open Your Eyes', 'SERIES', 'Unknown', 'Maria Wawreniuk, Ignacy Liss, Michał Sikorski, Wojciech Dolatowski, Klaudia Koścista, Zuzanna Galewicz, Marta Nieradkiewicz, Sara Celler Jezierska, Pola Król, Marcin Czarnik, Martyna Nowakowska', 'International', 2021, 'TV-MA', 84, 'After a tragic accident, an amnesiac teen tries to rebuild her life at a memory disorders center but becomes suspicious of her unconventional treatment.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s227', 'Post Mortem: No One Dies in Skarnes', 'SERIES', 'Unknown', 'Kathrine Thorborg Johansen, Elias Holmen Sørensen, André Sørum, Kim Fairchild, Sara Khorami, Terje Strømdahl, Øystein Røger, Marianne Jonger, Martin Karelius', 'International', 2021, 'TV-MA', 108, 'She''s back from the dead and has a newfound thirst for blood. Meanwhile, her family''s funeral parlor desperately needs more business. Hmm, what if...', 3.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s228', 'Really Love', 'MOVIE', 'Angel Kristi Williams', 'Kofi Siriboe, Yootha Wong-Loi-Sing, Michael Ealy, Uzo Aduba', 'United States', 2020, 'TV-MA', 95, 'A rising Black painter tries to break into a competitive art world while balancing an unexpected romance with an ambitious law student.', 4.2);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s229', 'The November Man', 'MOVIE', 'Roger Donaldson', 'Pierce Brosnan, Luke Bracey, Olga Kurylenko, Eliza Taylor, Caterina Scorsone, Bill Smitrovich, Will Patton, Amila Terzimehic, Lazar Ristovski, Mediha Musliovic', 'United States, United Kingdom', 2014, 'R', 108, 'An ex-CIA agent emerges from retirement to protect an important witness, but he soon discovers that old friends can make the most dangerous enemies.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s230', 'The Old Ways', 'MOVIE', 'Christopher Alender', 'Brigitte Kali Canales, Andrea Cortes, Julia Vera, Sal Lopez', 'United States', 2020, 'TV-MA', 90, 'A reporter visits her birthplace in Veracruz for a story about tribal culture, only to be kidnapped by locals who believe she''s demonically possessed.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s231', 'The River Runner', 'MOVIE', 'Rush Sturges', 'Various Artists', 'International', 2021, 'TV-MA', 86, 'In this documentary, a kayaker sets out to become the first man to paddle the four great rivers that flow from Tibet''s sacred Mount Kailash.', 3.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s232', 'The Water Man', 'MOVIE', 'David Oyelowo', 'David Oyelowo, Rosario Dawson, Lonnie Chavis, Amiah Miller, Alfred Molina, Maria Bello', 'United States', 2021, 'PG', 92, 'Desperate to save his ailing mother, 11-year-old Gunner runs away from home on a quest to find a mythic figure rumored to have the power to cheat death.', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s233', 'Wheel of Fortune', 'SERIES', 'Unknown', 'Pat Sajak, Vanna White', 'United States', 2019, 'TV-G', 87, 'Pat Sajak and Vanna White host one of TV''s most popular, long-running game shows, where players spin a wheel for prizes and solve mystery phrases.', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s234', 'Count Me In', 'MOVIE', 'Mark Lo', 'Various Artists', 'United Kingdom', 2021, 'TV-MA', 82, 'This documentary features some of rock''s greatest drummers as they come together in an inspiring rhythmic journey about the power of human connection.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s235', 'Oggy Oggy', 'SERIES', 'Unknown', 'Various Artists', 'International', 2021, 'TV-Y', 171, 'Join adorable kitten Oggy and his cast of cat pals in a bright and colorful kitty world. They''re always on the go for fun times and fantastic adventures!', 4.3);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s236', 'Untold: Caitlyn Jenner', 'MOVIE', 'Crystal Moselle', 'Various Artists', 'International', 2021, 'TV-PG', 70, 'Caitlyn Jenner''s unlikely path to Olympic glory was inspirational. But her more challenging road to embracing her true self proved even more meaningful.', 4.1);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s237', 'Boomika', 'MOVIE', 'Rathindran R Prasad', 'Aishwarya Rajesh, Vidhu, Surya Ganapathy, Madhuri, Pavel Navageethan, Avantika Vandanapu', 'International', 2021, 'TV-14', 122, 'Paranormal activity at a lush, abandoned property alarms a group eager to redevelop the site, but the eerie events may not be as unearthly as they think.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s238', 'Boomika (Hindi)', 'MOVIE', 'Rathindran R Prasad', 'Aishwarya Rajesh, Vidhu, Surya Ganapathy, Madhuri, Pavel Navageethan, Avantika Vandanapu', 'International', 2021, 'TV-14', 122, 'Paranormal activity at a lush, abandoned property alarms a group eager to redevelop the site, but the eerie events may not be as unearthly as they think.', 4.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s239', 'Boomika (Malayalam)', 'MOVIE', 'Rathindran R Prasad', 'Aishwarya Rajesh, Vidhu, Surya Ganapathy, Madhuri, Pavel Navageethan, Avantika Vandanapu', 'International', 2021, 'TV-14', 122, 'Paranormal activity at a lush, abandoned property alarms a group eager to redevelop the site, but the eerie events may not be as unearthly as they think.', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s240', 'Boomika (Telugu)', 'MOVIE', 'Rathindran R Prasad', 'Aishwarya Rajesh, Vidhu, Surya Ganapathy, Madhuri, Pavel Navageethan, Avantika Vandanapu', 'International', 2021, 'TV-14', 122, 'Paranormal activity at a lush, abandoned property alarms a group eager to redevelop the site, but the eerie events may not be as unearthly as they think.', 5.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s241', 'The Witcher: Nightmare of the Wolf', 'MOVIE', 'Han Kwang Il', 'Theo James, Mary McDonnell, Lara Pulver, Graham McTavish, Tom Canton, David Errigo Jr, Jennifer Hale, Kari Wahlgren, Matt Yang King, Darryl Kurylo, Keith Ferguson', 'International', 2021, 'TV-MA', 84, 'Escaping from poverty to become a witcher, Vesemir slays monsters for coin and glory, but when a new menace rises, he must face the demons of his past.', 3.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s242', 'Manifest', 'SERIES', 'Unknown', 'Melissa Roxburgh, Josh Dallas, Athena Karkanis, J.R. Ramirez, Luna Blaise, Jack Messina, Parveen Kaur', 'United States', 2021, 'TV-14', 126, 'When a plane mysteriously lands years after takeoff, the people onboard return to a world that has moved on without them and face strange, new realities.', 3.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s243', 'Comedy Premium League', 'SERIES', 'Unknown', 'Various Artists', 'International', 2021, 'TV-MA', 105, 'With satirical sketches, cheeky debates and blistering roasts, 16 of India’s wittiest entertainers compete in teams to be named the ultimate comedy champs.', 4.5);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s244', 'Everything Will Be Fine', 'SERIES', 'Unknown', 'Lucía Uribe, Flavio Medina, Isabella Vazquez Morales, Pierre Louis, Mercedes Hernández', 'International', 2021, 'TV-MA', 126, 'A separated couple live together for their child''s sake in this satirical dramedy about what it means to be a good parent and spouse in today''s world.', 4.7);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s245', 'Gunshot', 'MOVIE', 'Karim El Shenawy', 'Ahmed El Fishawy, Ruby, Mohamed Mamdouh, Ahmed Malek, Asmaa Abulyazeid, Samy Maghawry, Safaa El-Toukhy, Ahmed Kamal, Arfa Abdel Rassoul, Hana Shiha', 'International', 2018, 'TV-14', 96, 'After a clash at a protest ends in bloodshed, a forensic doctor and a journalist embark on a search for the elusive truth.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s246', 'Korean Cold Noodle Rhapsody', 'SERIES', 'Unknown', 'Paik Jong-won', 'International', 2021, 'TV-PG', 138, 'Refreshing and flavorful, naengmyeon is Korea''s coolest summertime staple. A journey through its history begins, from how it''s cooked to how it''s loved.', 5.0);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s247', 'Man in Love', 'MOVIE', 'Yin Chen-hao', 'Roy Chiu, Ann Hsu, Tsai Chen-nan, Chung Hsin-ling, Lan Wei-hua, Peace Yang, Huang Lu Tz-yin', 'International', 2021, 'TV-MA', 115, 'When he meets a debt-ridden woman who''s caring for her ailing father, a debt collector with a heart of gold sets out to win her love.', 4.6);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s248', 'Sweet Girl', 'MOVIE', 'Brian Andrew Mendoza', 'Jason Momoa, Isabela Merced, Manuel Garcia-Rulfo, Amy Brenneman, Adria Arjona, Raza Jaffrey, Justin Bartha, Lex Scott Davis, Michael Raymond-James', 'United States', 2021, 'R', 110, 'He lost the love of his life to a pharmaceutical company''s greed. Now his daughter is without a mother, and he''s without justice. For now.', 4.9);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s249', 'The Chair', 'SERIES', 'Unknown', 'Sandra Oh, Jay Duplass, Holland Taylor, David Morse, Bob Balaban, Nana Mensah, Everly Carganilla', 'International', 2021, 'TV-MA', 105, 'At a major university, the first woman of color to become chair tries to meet the dizzying demands and high expectations of a failing English department.', 4.8);
INSERT INTO CONTENT (show_id, title, type, director, cast_members, country, release_year, age_rating, duration_min, description, rating_avg) VALUES ('s250', 'The Loud House Movie', 'MOVIE', 'Dave Needham', 'Asher Bishop, David Tennant, Michelle Gomez, Jill Talley, Brian Stepanek, Catherine Taber, Liliana Mumy, Nika Futterman, Cristina Pucelli, Jessica DiCicco, Grey Griffin, Lara Jill Miller', 'International', 2021, 'TV-Y7', 88, 'With his parents and all 10 sisters in tow, Lincoln Loud heads to Scotland and learns that royalty runs in the family in this global musical journey!', 5.0);
COMMIT;




-- SECTION 9 : CONTENT_GENRE BRIDGE DATA  (559 M:N links)

INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (1, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (2, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (2, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (2, 33);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (3, 8);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (3, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (3, 29);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (4, 11);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (4, 22);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (5, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (5, 24);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (5, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (6, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (6, 32);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (6, 33);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (7, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (8, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (8, 15);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (8, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (9, 4);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (9, 22);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (10, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (10, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (11, 8);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (11, 11);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (11, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (12, 8);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (12, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (12, 29);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (13, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (13, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (14, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (14, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (15, 4);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (15, 8);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (15, 11);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (16, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (16, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (17, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (17, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (18, 8);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (18, 27);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (18, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (19, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (20, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (20, 27);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (20, 29);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (21, 8);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (21, 11);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (21, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (22, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (22, 29);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (22, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (23, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (23, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (24, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (25, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (25, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (25, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (26, 11);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (26, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (26, 22);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (27, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (27, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (27, 21);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (28, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (29, 14);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (29, 25);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (30, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (31, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (31, 15);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (31, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (32, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (33, 4);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (33, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (33, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (34, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (34, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (34, 36);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (35, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (36, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (36, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (36, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (37, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (37, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (37, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (38, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (38, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (39, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (39, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (40, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (41, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (41, 34);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (42, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (42, 6);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (42, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (43, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (43, 14);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (43, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (44, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (44, 14);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (44, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (45, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (45, 14);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (45, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (46, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (47, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (48, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (48, 24);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (48, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (49, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (49, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (50, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (50, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (51, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (51, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (51, 34);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (52, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (52, 2);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (52, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (53, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (53, 2);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (53, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (54, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (54, 2);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (54, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (55, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (55, 2);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (55, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (56, 22);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (57, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (57, 2);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (57, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (58, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (58, 2);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (58, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (59, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (59, 2);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (59, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (60, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (60, 2);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (60, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (61, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (61, 2);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (61, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (62, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (62, 2);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (62, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (63, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (63, 2);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (63, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (64, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (64, 2);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (64, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (65, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (66, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (67, 11);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (67, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (68, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (68, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (69, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (69, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (69, 28);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (70, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (70, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (71, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (71, 22);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (71, 24);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (72, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (73, 4);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (73, 11);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (73, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (74, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (74, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (75, 22);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (76, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (77, 3);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (77, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (78, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (78, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (79, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (79, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (79, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (80, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (80, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (80, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (81, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (82, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (83, 8);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (83, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (83, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (84, 22);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (85, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (85, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (85, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (86, 3);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (86, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (87, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (87, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (88, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (88, 19);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (89, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (89, 28);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (90, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (91, 25);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (91, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (92, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (92, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (93, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (93, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (93, 33);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (94, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (94, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (94, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (95, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (95, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (96, 22);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (97, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (97, 21);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (98, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (98, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (98, 34);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (99, 4);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (99, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (100, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (100, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (101, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (102, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (102, 28);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (103, 11);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (103, 26);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (104, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (104, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (104, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (105, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (105, 19);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (106, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (106, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (106, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (107, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (107, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (108, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (108, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (109, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (109, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (109, 37);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (110, 8);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (110, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (110, 27);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (111, 11);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (111, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (111, 27);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (112, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (113, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (114, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (114, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (115, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (115, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (115, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (116, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (116, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (117, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (117, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (117, 15);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (118, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (119, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (119, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (119, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (120, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (120, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (120, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (121, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (121, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (122, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (122, 24);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (122, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (123, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (124, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (125, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (125, 19);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (126, 8);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (126, 29);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (126, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (127, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (127, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (127, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (128, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (128, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (129, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (129, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (129, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (130, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (131, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (131, 21);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (132, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (132, 6);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (132, 9);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (133, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (133, 29);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (133, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (134, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (134, 25);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (135, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (135, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (136, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (137, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (137, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (138, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (138, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (139, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (139, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (140, 6);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (140, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (140, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (141, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (141, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (141, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (142, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (143, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (144, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (144, 25);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (145, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (145, 9);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (146, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (146, 9);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (146, 21);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (147, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (147, 21);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (148, 22);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (149, 35);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (150, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (150, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (151, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (152, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (152, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (153, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (154, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (155, 3);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (155, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (155, 37);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (156, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (156, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (156, 9);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (157, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (157, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (157, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (158, 25);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (158, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (159, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (159, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (160, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (160, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (160, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (161, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (162, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (162, 9);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (162, 25);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (163, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (164, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (164, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (165, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (165, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (166, 8);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (166, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (166, 27);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (167, 6);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (167, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (168, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (168, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (169, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (169, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (169, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (170, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (170, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (171, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (171, 21);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (172, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (172, 13);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (173, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (173, 21);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (174, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (174, 20);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (175, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (175, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (176, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (176, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (177, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (177, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (178, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (178, 6);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (179, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (179, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (180, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (180, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (181, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (181, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (182, 11);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (183, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (184, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (184, 6);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (185, 22);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (186, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (186, 28);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (187, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (187, 24);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (187, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (188, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (188, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (189, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (189, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (190, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (190, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (191, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (191, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (192, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (192, 15);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (193, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (193, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (193, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (194, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (194, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (195, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (195, 27);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (195, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (196, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (196, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (196, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (197, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (197, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (198, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (198, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (199, 8);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (199, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (199, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (200, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (200, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (200, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (201, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (201, 14);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (201, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (202, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (202, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (202, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (203, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (203, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (203, 21);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (204, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (204, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (205, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (205, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (206, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (206, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (206, 25);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (207, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (207, 15);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (207, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (208, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (208, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (208, 21);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (209, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (209, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (209, 21);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (210, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (210, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (210, 21);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (211, 14);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (211, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (212, 14);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (212, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (213, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (213, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (214, 11);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (214, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (215, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (215, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (216, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (216, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (216, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (217, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (217, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (217, 15);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (218, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (218, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (218, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (219, 22);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (219, 37);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (220, 3);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (220, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (221, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (221, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (222, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (223, 8);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (223, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (223, 33);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (224, 8);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (224, 11);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (224, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (225, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (225, 22);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (226, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (226, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (226, 33);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (227, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (227, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (227, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (228, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (228, 15);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (228, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (229, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (230, 14);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (231, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (231, 28);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (232, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (232, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (233, 22);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (234, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (234, 21);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (235, 18);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (235, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (236, 10);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (236, 20);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (236, 28);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (237, 14);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (237, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (237, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (238, 14);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (238, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (238, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (239, 14);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (239, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (239, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (240, 14);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (240, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (240, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (241, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (241, 2);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (242, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (242, 33);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (242, 34);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (243, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (243, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (244, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (244, 27);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (244, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (245, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (245, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (245, 38);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (246, 11);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (246, 17);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (247, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (247, 16);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (247, 23);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (248, 1);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (248, 12);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (249, 30);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (249, 31);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (250, 5);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (250, 7);
INSERT INTO CONTENT_GENRE (content_id, genre_id) VALUES (250, 21);
COMMIT;



-- SECTION 10 : USER DATA  (demo accounts)

INSERT INTO USER_ACCOUNT (name, email, phone, password)
  VALUES ('Charishma', 'demo@streamverse.com', '9876543210', 'demo1234');
INSERT INTO USER_ACCOUNT (name, email, phone, password)
  VALUES ('Krapa', 'krapa@streamverse.com', '9123456789', 'krapa1234');
INSERT INTO USER_ACCOUNT (name, email, phone, password)
  VALUES ('Rohan Das', 'rohan@gmail.com', '9988776655', 'rohan1234');
INSERT INTO USER_ACCOUNT (name, email, phone, password)
  VALUES ('Anjali Rao', 'anjali@gmail.com', '9871234560', 'anjali1234');
INSERT INTO USER_ACCOUNT (name, email, phone, password)
  VALUES ('Vikram Nair', 'vikram@gmail.com', '9765432109', 'vikram1234');
COMMIT;



-- SECTION 11 : SUBSCRIPTIONS — TRIGGER DEMO
--   Note: Only user_id and plan_id are inserted.
--         trg_calc_end_date  → fills end_date automatically
--         trg_auto_payment   → inserts payment record automatically
--         trg_expire_subscriptions → marks EXPIRED if past end_date

INSERT INTO USER_SUBSCRIPTION (user_id, plan_id) VALUES (1, 4); -- Charishma: Premium 4K
INSERT INTO USER_SUBSCRIPTION (user_id, plan_id) VALUES (2, 3); -- Krapa: Standard 1080p
INSERT INTO USER_SUBSCRIPTION (user_id, plan_id) VALUES (3, 1); -- Rohan: Mobile
INSERT INTO USER_SUBSCRIPTION (user_id, plan_id) VALUES (4, 5); -- Anjali: Annual
INSERT INTO USER_SUBSCRIPTION (user_id, plan_id) VALUES (5, 2); -- Vikram: Basic HD
COMMIT;



-- SECTION 12 : SAMPLE WATCH HISTORY

INSERT INTO WATCH_HISTORY (user_id, content_id, progress_pct) VALUES (1, 34,  100); -- Charishma: Squid Game
INSERT INTO WATCH_HISTORY (user_id, content_id, progress_pct) VALUES (1,  2,   75); -- Charishma: Blood & Water
INSERT INTO WATCH_HISTORY (user_id, content_id, progress_pct) VALUES (1, 33,   50); -- Charishma: Sex Education
INSERT INTO WATCH_HISTORY (user_id, content_id, progress_pct) VALUES (2, 34,  100); -- Krapa: Squid Game
INSERT INTO WATCH_HISTORY (user_id, content_id, progress_pct) VALUES (2,110,   80); -- Krapa: La Casa de Papel
INSERT INTO WATCH_HISTORY (user_id, content_id, progress_pct) VALUES (3, 82,  100); -- Rohan: Kate
INSERT INTO WATCH_HISTORY (user_id, content_id, progress_pct) VALUES (3, 42,   60); -- Rohan: Jaws
INSERT INTO WATCH_HISTORY (user_id, content_id, progress_pct) VALUES (4,128,  100); -- Anjali: A Cinderella Story
INSERT INTO WATCH_HISTORY (user_id, content_id, progress_pct) VALUES (4,139,  100); -- Anjali: Dear John
INSERT INTO WATCH_HISTORY (user_id, content_id, progress_pct) VALUES (5,192,   90); -- Vikram: Wind River
INSERT INTO WATCH_HISTORY (user_id, content_id, progress_pct) VALUES (1, 20,  100); -- Charishma: Jaguar
INSERT INTO WATCH_HISTORY (user_id, content_id, progress_pct) VALUES (2,187,   40); -- Krapa: Hometown Cha-Cha-Cha
COMMIT;


-- SECTION 13 : SAMPLE RATINGS

INSERT INTO RATING (user_id, content_id, rating_value) VALUES (1,  34, 5);
INSERT INTO RATING (user_id, content_id, rating_value) VALUES (1,  33, 5);
INSERT INTO RATING (user_id, content_id, rating_value) VALUES (1,   2, 4);
INSERT INTO RATING (user_id, content_id, rating_value) VALUES (2,  34, 5);
INSERT INTO RATING (user_id, content_id, rating_value) VALUES (2, 110, 5);
INSERT INTO RATING (user_id, content_id, rating_value) VALUES (3,  82, 4);
INSERT INTO RATING (user_id, content_id, rating_value) VALUES (4, 128, 5);
INSERT INTO RATING (user_id, content_id, rating_value) VALUES (4, 139, 5);
INSERT INTO RATING (user_id, content_id, rating_value) VALUES (5, 192, 4);
COMMIT;



-- SECTION 14 : QUERY SHOWCASE

-- Run each block individually or all at once.


-- ── BASIC QUERIES 

-- B1 : All users
SELECT user_id, name, email, phone, join_date, status
FROM   USER_ACCOUNT
ORDER  BY join_date DESC;

-- B2 : All subscription plans
SELECT * FROM SUBSCRIPTION_PLAN ORDER BY price;

-- B3 : All active subscriptions
SELECT * FROM USER_SUBSCRIPTION WHERE status = 'ACTIVE';

-- B4 : Search content by keyword  (change 'squid' to any search term)
SELECT title, type, release_year, age_rating, rating_avg
FROM   CONTENT
WHERE  LOWER(title) LIKE LOWER('%squid%')
ORDER  BY rating_avg DESC;

-- B5 : Filter content by type
SELECT title, release_year, duration_min, age_rating
FROM   CONTENT
WHERE  type = 'MOVIE'
ORDER  BY rating_avg DESC;

-- B6 : All payments
SELECT p.payment_id, ua.name AS user_name, sp.plan_name,
       p.amount, p.mode, p.paid_on
FROM   PAYMENT p
JOIN   USER_SUBSCRIPTION us ON p.sub_id     = us.sub_id
JOIN   USER_ACCOUNT      ua ON us.user_id   = ua.user_id
JOIN   SUBSCRIPTION_PLAN sp ON us.plan_id   = sp.plan_id
ORDER  BY p.paid_on DESC;


-- ── COMPLEX QUERIES 

-- C1 : Full subscription details (3-table JOIN)
SELECT ua.name, ua.email,
       sp.plan_name, sp.price, sp.resolution, sp.max_devices,
       us.start_date, us.end_date,
       FLOOR(us.end_date - SYSDATE) AS days_remaining,
       us.status
FROM   USER_ACCOUNT      ua
JOIN   USER_SUBSCRIPTION us ON ua.user_id = us.user_id
JOIN   SUBSCRIPTION_PLAN sp ON us.plan_id = sp.plan_id
ORDER  BY us.start_date DESC;

-- C2 : Revenue breakdown by plan  (GROUP BY + aggregate functions)
SELECT sp.plan_name,
       COUNT(p.payment_id)       AS total_transactions,
       SUM(p.amount)             AS total_revenue,
       ROUND(AVG(p.amount), 2)   AS avg_revenue
FROM   SUBSCRIPTION_PLAN sp
LEFT JOIN USER_SUBSCRIPTION us ON sp.plan_id   = us.plan_id
LEFT JOIN PAYMENT           p  ON us.sub_id     = p.sub_id
GROUP  BY sp.plan_name
ORDER  BY total_revenue DESC NULLS LAST;

-- C3 : Most watched content  (GROUP BY + HAVING)
SELECT c.title, c.type,
       COUNT(wh.watch_id)        AS watch_count,
       SUM(c.duration_min)       AS total_watch_mins
FROM   CONTENT      c
JOIN   WATCH_HISTORY wh ON c.content_id = wh.content_id
GROUP  BY c.title, c.type
HAVING COUNT(wh.watch_id) >= 1
ORDER  BY watch_count DESC;

-- C4 : Content with ALL their genres  (LISTAGG — multi-genre JOIN)
SELECT c.title, c.type, c.release_year,
       LISTAGG(g.genre_name, ', ') WITHIN GROUP (ORDER BY g.genre_name) AS genres
FROM   CONTENT       c
JOIN   CONTENT_GENRE cg ON c.content_id = cg.content_id
JOIN   GENRE          g ON cg.genre_id  = g.genre_id
GROUP  BY c.title, c.type, c.release_year
ORDER  BY c.title;

-- C5 : Users who have NEVER watched anything  (NOT IN subquery)
SELECT name, email, join_date
FROM   USER_ACCOUNT
WHERE  user_id NOT IN (SELECT DISTINCT user_id FROM WATCH_HISTORY);

-- C6 : Binge-watchers — above-average total watch time  (Correlated subquery)
SELECT ua.name,
       SUM(c.duration_min) AS total_mins_watched
FROM   USER_ACCOUNT  ua
JOIN   WATCH_HISTORY wh ON ua.user_id    = wh.user_id
JOIN   CONTENT        c ON wh.content_id = c.content_id
GROUP  BY ua.name
HAVING SUM(c.duration_min) > (
         SELECT AVG(sub.total) FROM (
           SELECT SUM(c2.duration_min) AS total
           FROM   WATCH_HISTORY wh2
           JOIN   CONTENT c2 ON wh2.content_id = c2.content_id
           GROUP  BY wh2.user_id
         ) sub
       )
ORDER  BY total_mins_watched DESC;

-- C7 : Top-rated content with user ratings  (uses VIEW)
SELECT * FROM CONTENT_STATS_V
WHERE  user_rating_count > 0
ORDER  BY avg_user_rating DESC;

-- C8 : Active subscriber dashboard  (uses VIEW)
SELECT * FROM ACTIVE_SUBSCRIBERS_V
ORDER  BY days_remaining ASC;

-- C9 : Content by a specific genre  (genre filter via bridge table)
SELECT c.title, c.type, c.release_year
FROM   CONTENT c
WHERE  c.content_id IN (
         SELECT cg.content_id
         FROM   CONTENT_GENRE cg
         JOIN   GENRE g ON cg.genre_id = g.genre_id
         WHERE  LOWER(g.genre_name) LIKE '%drama%'
       )
ORDER  BY c.rating_avg DESC;

-- C10 : Revenue trend — cumulative payments  (analytic / window function)
SELECT p.payment_id, ua.name, sp.plan_name, p.amount, p.paid_on,
       SUM(p.amount) OVER (ORDER BY p.paid_on ROWS UNBOUNDED PRECEDING) AS cumulative_revenue
FROM   PAYMENT p
JOIN   USER_SUBSCRIPTION us ON p.sub_id   = us.sub_id
JOIN   USER_ACCOUNT      ua ON us.user_id = ua.user_id
JOIN   SUBSCRIPTION_PLAN sp ON us.plan_id = sp.plan_id
ORDER  BY p.paid_on;


-- ── TRIGGER VERIFICATION 

-- TV1 : Confirm trg_calc_end_date fired → end_date is populated
SELECT sub_id, user_id, plan_id, start_date, end_date, status
FROM   USER_SUBSCRIPTION;

-- TV2 : Confirm trg_auto_payment fired → payment records exist
SELECT * FROM PAYMENT;


-- ── PROCEDURE TESTING 

-- PT1 : Call get_total_revenue
DECLARE
  v_total NUMBER;
BEGIN
  get_total_revenue(v_total);
  DBMS_OUTPUT.PUT_LINE('=================================');
  DBMS_OUTPUT.PUT_LINE('Total Platform Revenue: Rs. ' || v_total);
  DBMS_OUTPUT.PUT_LINE('=================================');
END;
/

-- PT2 : Call get_user_report for user 1
DECLARE
  v_name       VARCHAR2(100);
  v_plan       VARCHAR2(50);
  v_status     VARCHAR2(15);
  v_days_left  NUMBER;
  v_watch_mins NUMBER;
BEGIN
  get_user_report(1, v_name, v_plan, v_status, v_days_left, v_watch_mins);
  DBMS_OUTPUT.PUT_LINE('=================================');
  DBMS_OUTPUT.PUT_LINE('User:          ' || v_name);
  DBMS_OUTPUT.PUT_LINE('Plan:          ' || v_plan);
  DBMS_OUTPUT.PUT_LINE('Status:        ' || v_status);
  DBMS_OUTPUT.PUT_LINE('Days Left:     ' || v_days_left);
  DBMS_OUTPUT.PUT_LINE('Watch Time:    ' || v_watch_mins || ' mins');
  DBMS_OUTPUT.PUT_LINE('=================================');
END;
/

