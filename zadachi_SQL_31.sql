-- 189. “Знайти країни, з яких у нас найбільше клієнтів”

WITH level1 as(SELECT country
	   ,count(*) as count_orders
FROM customers 
GROUP BY country)
SELECT *
       ,dense_rank () over (order by count_orders DESC) as ranks
FROM level1

-- 190. Знайти клієнтів, які робили замовлення мінімум у 3 різних місяцях підряд.

WITH level1 as(SELECT DISTINCT date_trunc('month', order_date) as date
       ,customer_id
FROM orders
JOIN order_details USING(order_id)
ORDER BY customer_id, date),
level2 as(SELECT customer_id
       ,date
	   ,(EXTRACT (year from date) *12 +EXTRACT (month from date)) as month_index
	   ,ROW_number() OVER (PARTITION BY customer_id ORDER BY date) as rn
FROm level1),
level3 as(SELECT *
       ,month_index - rn as group_id
FROM level2)
SELECT customer_id
       ,group_id
	   ,COUNT(*) as series_length
from level3
GROUP BY customer_id, group_id
HAVING COUNT(*) >= 3
ORDER BY customer_id, group_id

-- 191. Знайти клієнтів, у яких середній чек (per order) демонструє 
-- стабільне зростання у 3+ послідовних замовленнях.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1),
level3 as(SELECT *
       ,case when sum_chek > prev_chek THEN 1 ELSE 0 END flag_chek
FROM level2),
level4 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id ORDER BY order_date) as rn
FROM level3),
level5 as(SELECT *
       ,SUM(flag_chek) OVER (PARTITION BY customer_id ORDER BY order_date ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS rn2
FROM level4),
level6 as(SELECT *
       ,rn - rn2 as group_id
FROM level5
ORDER BY customer_id, order_date)
SELECT customer_id
       ,group_id
	   ,COUNT(*) as count_order
FROM level6
GROUP BY customer_id, group_id
HAVING COUNT(*) >= 3
ORDER BY customer_id, group_id

-- 192. “Клієнти зі стабільним ростом інтересу: знайти тих, у кого середній 
-- чек зростав у кожному наступному кварталі”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date
ORDER BY customer_id, order_date),
level2 as(SELECT *
       ,EXTRACT(year from order_date) as year
	   ,EXTRACT(month from order_date) as month
FROM level1),
level3 as(SELECT *
       ,case when month in (1,2,3) THEN 1
	   when month in (4,5,6) THEN 2
	   when month in (7,8,9) THEN 3
	   when month in (10,11,12) THEN 4
	   END as quartals
FROM level2),
level4 as(SELECT customer_id
       ,year
	   ,quartals
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
FROM level3
GROUP BY customer_id,year,quartals
ORDER BY customer_id,year,quartals),
level5 as(SELECT *
       ,LEAD(avg_chek) OVER (partition by customer_id ORDER BY year, quartals) as prev_avg_chek
FROM level4),
level6 as(SELECT *
       ,COUNT(*) OVER (partition by customer_id) as real_count_order
	   ,case when avg_chek < prev_avg_chek THEN 1 ELSE 0 END as flag_chek
FROM level5
WHERE prev_avg_chek is not null),
level7 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level6)
SELECT *
FROM level7
WHERE real_count_order = sum_flag_chek

-- 193. Знайти клієнтів, у яких:
-- середній чек зменшується кожного наступного кварталу
-- але загальна кількість товарів у кварталі зростає в ті ж самі квартали

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,SUM(quantity) as sum_quantity
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,EXTRACT(year from order_date) as year
	   ,EXTRACT(month from order_date) as month
FROM level1),
level3 as(SELECT *
       ,case when month IN (1,2,3) THEN 1
	   when month IN (4,5,6) THEN 2
	   when month IN (7,8,9) THEN 3
	   when month IN (10,11,12) THEN 4
	   END as quartals
FROM level2),
level4 as(SELECT customer_id
       ,year
	   ,quartals
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,SUM(sum_quantity) as sum_quantity_per_quartal
FROM level3
GROUP BY customer_id, year, quartals
ORDER BY customer_id, year, quartals),
level5 as(SELECT *
       ,LAG(avg_chek) OVER (partition by customer_id order by year,quartals) as prev_avg_chek
	   ,LAG(sum_quantity_per_quartal) OVER (partition by customer_id order by year, quartals) as prev_sum_quantity_per_quartal
FROM level4),
level6 as(SELECT *
       ,case when avg_chek < prev_avg_chek THEN 1 ELSE 0 END as flag_chek
	   ,case when sum_quantity_per_quartal > prev_sum_quantity_per_quartal THEN 1 ELSE 0 END as flag_quantity
	   ,COUNT(*) OVER (partition by customer_id) as real_count_order
FROM level5
WHERE prev_avg_chek is not null),
level7 as(SELECT *
       ,case when flag_chek = 1 AND flag_quantity = 1 THEN 1 ELSE 0 END as tendention_flag
FROM level6),
level8 as(SELECT *
       ,SUM(tendention_flag) OVEr (partition by customer_id) as sum_tendention_flag
FROM level7)
SELECT *
FROM level8
WHERE sum_tendention_flag = real_count_order

-- 194. “Клієнти з ефектом цінової лояльності:
-- коли клієнт купує товари лише в певному ціновому коридорі

WITH level1 as(SELECT customer_id
	   ,ROUND((unit_price * (1-discount))::numeric,2) as price_per_unit
FROM orders
JOIN order_details USING(order_id)
ORDER BY customer_id),
level2 as(SELECT customer_id
       ,MAX(price_per_unit) as max_price
	   ,MIN(price_per_unit) as min_price
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,max_price - min_price as spread
FROM level2)
SELECT *
FROM level3
WHERE spread <= 15

-- 195. Ми хочемо знайти клієнтів, у яких є інверсія поведінки:
-- їхні дешеві замовлення (перший квартиль) → з часом стають дорожчими
-- їхні дорогі замовлення (четвертий квартиль) → з часом стають дешевшими
-- Тобто клієнт “зближує” низький і високий сегмент цін.

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id,order_id, order_date),
level2 as(SELECT *
       ,NTILE(4) over (partition by customer_id order by sum_chek) as quartil
	   ,NTILE(2) over (partition by customer_id order by order_date) as halfs
FROM level1),
level3 as(SELECT customer_id
       ,quartil
	   ,halfs
	   ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
FROM level2
GROUP BY customer_id,quartil,halfs
ORDER BY customer_id,quartil,halfs)
SELECT customer_id
       ,ROUND(AVG(case when quartil = 1 AND halfs = 1 THEN avg_chek END)::numeric,2) as q1_first
	   ,ROUND(AVG(case when quartil = 1 AND halfs = 2 THEN avg_chek END)::numeric,2) as q1_second
	   ,ROUND(AVG(case when quartil = 4 AND halfs = 1 THEN avg_chek END)::numeric,2) as q4_first
	   ,ROUND(AVG(case when quartil = 4 AND halfs = 2 THEN avg_chek END)::numeric,2) as q4_second
FROM level3
GROUP BY customer_id
HAVING AVG(case when quartil = 1 AND halfs = 2 THEN avg_chek END)
       > AVG(case when quartil = 1 AND halfs = 1 THEN avg_chek END) AND
	   AVG(case when quartil = 4 AND halfs = 2 THEN avg_chek END)
	   < AVG(case when quartil = 4 AND halfs = 1 THEN avg_chek END)


