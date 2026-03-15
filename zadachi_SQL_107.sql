-- 705. «Клієнт із ефектом фантомної лояльності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,FIRST_VALUE (order_date) OVER (partition by customer_id order by order_date) as first_date
	   ,FIRST_VALUE (order_date) OVER (partition by customer_id order by order_date DESC) as last_date  
FROm orders),
level2 as(SELECT *
       ,case when order_date = first_date THEN 'first'
	   when order_date = last_date THEN 'last'
	   else 'other' END as gradation
FROM level1),
level3 as(SELECT *
	   ,last_date - first_date as count_day 
FROm level2),
level4 as(SELECT customer_id
       ,COUNT(DISTINCT order_date) as count_unik_date
FROM level3
WHERE gradation = 'other'
GROUP By customer_id),
level5 as(SELECT *
FROM level3
JOIN level4 USING (customer_id))
SELECT DISTINCT customer_id
       ,first_date
	   ,last_date
	   ,count_unik_date
	   ,count_day
FROM level5
WHERE count_unik_date = 2 AND count_day >= 365

-- 706. «Клієнт з ефектом прихованої концентрації»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,sum(quantity) as sum_quantity
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,MAX(sum_quantity) OVER (partition by customer_id) as max_quantity
	   ,SUM(sum_quantity) OVER (partition by customer_id) as total_quantity
FROM level1),
level3 as(SELECT *
       ,ROUND((max_quantity::numeric / total_quantity::numeric),4) as ratio_quantity
FROM level2)
SELECT *
FROm level3
WHERE ratio_quantity >= 0.6

-- 707. «Клієнт із ефектом одноденного монополіста»

WITH level1 as(SELECT customer_id
	   ,order_date
	   ,SUM(unit_price * quantity * (1-discount)) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_date),
level2 as(SELECT *
       ,ROUND(MAX(sum_chek) OVER (partition by customer_id)::numeric,2) as max_chek
	   ,ROUND(SUM(sum_chek) OVER (partition by customer_id)::numeric,2) as total_chek
FROM level1),
level3 as(SELECT *
       ,ROUND((max_chek / total_chek),4) as ratio_chek
FROM level2)
SELECT DISTINCT customer_id
       ,max_chek
	   ,total_chek
	   ,ratio_chek
FROM level3
WHERE ratio_chek >= 0.7

-- 708. «Клієнт з ефектом фальшивої регулярності»

WITH level1 as(SELECT DISTINCT customer_id
	   ,order_date
FROM orders),
level2 as(SELECT *
       ,LEAD(order_date) OVER (partition by customer_id order by order_date) as next_date 
FROM level1),
level3 as(SELECT *
       ,next_date - order_date as interval
FROM level2
WHERE next_date is not null),
level4 as(SELECT *
       ,ROUND(AVG(interval) OVER (partition by customer_id)::numeric,2) as avg_interval
	   ,case when interval <= 3 THEN 1 ELSE 0 END as flag_interval
FROm level3),
level5 as(SELECT *
       ,SUM(flag_interval) OVER (partition by customer_id) as sum_flag_interval
FROm level4)
SELECT *
FROm level5
WHERE sum_flag_interval >= 1 AND avg_interval >= 30

-- 709. «Клієнт з ефектом структурного перелому»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND((count_order * 0.3)::numeric,0) as count_30_percent
	   ,ROUND((count_order * 0.7)::numeric,0) as count_70_percent
FROM level1
WHERE count_order >= 12),
level3 as(SELECT *
       ,case when rn <= count_30_percent THEN 'first_third'
	   when rn > count_30_percent AND rn <= count_70_percent THEN 'second_third'
	   when rn > count_70_percent THEN 'third_third'
	   END as gradation
FROm level2),
level4 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'first_third') OVER (partition by customer_id)::numeric,2) as avg_chek_first_third
	   ,ROUND(AVG(sum_chek) FILTER (WHERE gradation = 'third_third') OVER (partition by customer_id)::numeric,2) as avg_chek_third_third
FROm level3),
level5 as(SELECT DISTINCT customer_id
       ,count_order
	   ,count_30_percent
	   ,count_70_percent
	   ,avg_chek_first_third
	   ,avg_chek_third_third
       ,avg_chek_first_third / avg_chek_third_third as ratio_first_third
FROm level4)
SELECT *
FROM level5
WHERE ratio_first_third <= 0.5 OR ratio_first_third >= 2

-- 710. «Клієнт з ефектом латентної нестабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as stddev_chek
	   ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROm level1),
level3 as(SELECT DISTINCT customer_id
       ,stddev_chek
	   ,max_chek
	   ,avg_chek
	   ,ROUND((stddev_chek / avg_chek)::numeric,2) as cv
FROm level2)
SELECT *
FROm level3
WHERE cv <= 0.2

-- 711. «Клієнт із дзеркальною структурою покупок» - цю задачу зробив чатік, завтра потрібно спробувати самому

WITH level1 AS (SELECT customer_id,
           order_id,
           order_date,
           ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) AS sum_chek,
           COUNT(order_id) OVER (PARTITION BY customer_id) AS count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 AS (SELECT *,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date, order_id) AS rn,
           ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_date DESC, order_id DESC) AS rn_invert
FROM level1
WHERE count_order >= 10),
level3 AS (SELECT a.customer_id,
           a.rn,
           a.sum_chek AS chek_left,
           b.sum_chek AS chek_right,
           ABS(a.sum_chek - b.sum_chek) / NULLIF(a.sum_chek, 0) AS dev_ratio
FROM level2 a
JOIN level2 b ON a.customer_id = b.customer_id
AND b.rn = a.rn_invert -- щоб не рахувати пару двічі:
WHERE a.rn <= a.rn_invert),
level4 AS (SELECT customer_id,
           ROUND(AVG(dev_ratio)::numeric,4) AS avg_dev_ratio,
           MAX(dev_ratio) AS max_dev_ratio
FROM level3
GROUP BY customer_id)
SELECT *
FROM level4
WHERE max_dev_ratio <= 0.05;