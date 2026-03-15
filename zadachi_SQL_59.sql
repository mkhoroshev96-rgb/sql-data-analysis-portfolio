-- 374. «Клієнти з ілюзією стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2),2) as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first_half') OVER (partition by customer_id)::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second_half') OVER (partition by customer_id)::numeric,2) as avg_chek_second
FROM level2),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_second - avg_chek_first) / avg_chek_second)::numeric,2) as diff_avg_chek
	   ,ROUND((sum_chek / prev_chek)::numeric,2) as diff_chek
FROM level3)
SELECT *
FROm level4
WHERE diff_avg_chek <= 0.1 AND (diff_chek <= 0.5 OR diff_chek >= 1.5)

-- 375. «Клієнти з ілюзією зростання»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by sum_chek)::numeric,2) as median_chek
FROM level1
GROUP By customer_id),
level3 as(SELECT *
       ,ROUND((avg_chek / median_chek)::numeric,2) as diff_chek
FROm level1
JOIN level2 USING (customer_id)),
level4 as(SELECt *
       ,case when sum_chek < median_chek THEN 1 ELSE 0 END as flag_chek
FROM level3
WHERE diff_chek > 1.3),
level5 as(SELECT *
       ,SUM(flag_chek) OVER (partition by customer_id) as sum_flag_chek
FROM level4),
level6 as(SELECT *
       ,ROUND((sum_flag_chek::numeric / count_order::numeric),2) as ratio
FROM level5)
SELECT *
FROm level6
WHERE ratio > 0.5 

-- 376. «Клієнти з ефектом удаваної лояльності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROM level1),
level3 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROm orders
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND(AVG(count_order) OVER ()::numeric,2) as avg_count_order
FROM level3),
level5 as(SELECT *
FROm level2
JOIN level4 USING (customer_id)),
level6 as(SELECT DISTINCT customer_id
       ,avg_chek
	   ,total_revenue
	   ,count_order
	   ,avg_count_order
	   ,ROUND(AVG(avg_chek) OVER ()::numeric,2) as global_avg_chek
	   ,SUM(total_revenue) OVER () as global_total_revenue
FROm level5),
level7 as(SELECT *
       ,ROUND((total_revenue / global_total_revenue * 100)::numeric,2) as ratio
FROM level6)
SELECT *
FROm level7
WHERE count_order > avg_count_order AND avg_chek < global_avg_chek AND ratio < 1

-- 377. «Категорії з ефектом удаваної маржинальності»

WITh level1 as(SELECT category_id
       ,order_id
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by category_id) as count_order
FROm orders
JOIn order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
GROUP By category_id, order_id),
level2 as(SELECT category_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,percentile_cont(0.5) WITHIN GROUP (order by sum_chek) as median_chek
FROm level1
GROUP By category_id),
level3 as(SELECT *
       ,ROUND((avg_chek / median_chek)::numeric,2) as diff_chek
FROm level1 
JOIn level2 USING (category_id)
WHERE count_order > 20),
level4 as(SELECT *
       ,case when sum_chek < avg_chek THEN 1 ELSE 0 END as flag_chek
FROm level3
WHERE diff_chek >= 1.4),
level5 as(SELECT *
       ,SUM(flag_chek) OVER (partition by category_id) as sum_flag_chek
FROm level4),
level6 as(SELECT *
       ,ROUND((sum_flag_chek::numeric / count_order::numeric),2) as ratio
FROm level5)
SELECT *
FROM level6
WHERE ratio >= 0.6

-- 378. «Категорії з ефектом концентрації обороту»

WITh level1 as(SELECT category_id
       ,order_id
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by category_id) as count_order
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
GROUP By category_id, order_id),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by category_id) as total_revenue
FROM level1),
level3 as(SELECT *
       ,ROUND(((sum_chek / total_revenue)*100)::numeric,2) as ratio
FROm level2
WHERE count_order >= 30),
level4 as(SELECT *
       ,DENSE_RANK () OVER (partition by category_id ORDER BY sum_chek DESC) as rn_chek
	   ,NTILE(5) OVER (partition by category_id order By sum_chek DESC) as ntile_chek
FROm level3),
level5 as(SELECT *
       ,SUM(sum_chek) OVER (partition by category_id, ntile_chek) as sum_ntile_chek
FROm level4
WHERE ntile_chek = 1),
level6 as(SELECT *
       ,ROUND((sum_ntile_chek / total_revenue)::numeric,2) as ratio_1_ntile
FROm level5)
SELECT *
FROm level6
WHERE ratio_1_ntile >= 0.8

-- 379. «Категорії з фальшивою стабільністю цін»

WITh level1 as(SELECT category_id
       ,order_id
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by category_id) as count_order
FROm orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
GROUP By category_id, order_id),
level2 as(SELECT *
       ,ROUND((sum_chek / sum_quantity)::numeric,2) as avg_price_per_order
FROm level1
WHERE count_order >= 25),
level3 as(SELECT *
       ,AVG(avg_price_per_order) OVER (partition by category_id) as avg_price_per_category
	   ,STDDEV(avg_price_per_order) OVER (partition by category_id) as std_dev_price_per_category
FROm level2),
level4 as(SELECT *
       ,std_dev_price_per_category / avg_price_per_category as ratio
FROm level3)
SELECT *
FROm level4
WHERE ratio < 0.15

-- 380. «Клієнти з ефектом розмитого середнього»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id),
level2 as(SELECT customer_id
       ,ROUND(AVG(sum_chek)::numeric,2) as avg_chek
	   ,ROUND(percentile_cont(0.5) WITHIN GROUP (order by sum_chek)::numeric,2) as median_chek
FROm level1
GROUP By customer_id),
level3 as(SELECT *
       ,MAX(sum_chek) OVER (partition by customer_id) as max_chek
	   ,MIN(sum_chek) OVER (partition by customer_id) as min_chek
	   ,ROUND((median_chek / avg_chek)::numeric,2) as diff_chek
FROM level1
JOIn level2 USING (customer_id)
WHERE count_order >= 8)
SELECT *
       ,(max_chek + min_chek) / 2 as mid_range
FROm level3
WHERE diff_chek >= 1.25

-- 381. «Клієнти з ефектом інфляційного росту»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,ROUND((COUNT(order_id) OVER (partition by customer_id)::numeric / 2),2) as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROm orders
JOin order_details USING(order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,case when rn <= middle_point THEN 'first_half'
	   when rn > middle_point THEN 'second_half'
	   END as halfs
FROm level1
WHERE count_order >= 6),
level3 as(SELECt customer_id
       ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_quantity_second
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first_half')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second_half')::numeric,2) as avg_chek_second
FROm level2
GROUP By customer_id)
SELECT *
FROM level3
WHERE avg_quantity_first > avg_quantity_second AND avg_chek_first < avg_chek_second

-- 382. «Замовлення з перекосом структури»

WITh level1 as(SELECT order_id
       ,SUM(quantity) as sum_quantity
FROm orders
JOIN order_details USING (order_id)
GROUP By order_id),
level2 as(SELECT order_id
       ,COUNT(DISTINCT product_id) as unik_prod
FROm orders
JOIN order_details USING (order_id)
GROUP By order_id),
level3 as(SELECT *
FROm level1
JOIn level2 USING (order_id)),
level4 as(SELECT *
       ,ROUND(AVG(sum_quantity) OVER ()::numeric,2) as global_avg_quantity
	   ,ROUND(AVG(unik_prod) OVER ()::numeric,2) as global_unik_prod
FROM level3)
SELECT *
FROm level4
WHERE sum_quantity > global_avg_quantity AND unik_prod < global_unik_prod