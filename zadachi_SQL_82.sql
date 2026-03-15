-- 523. «Клієнт з ілюзією різноманіття»

WITH level1 as(SELECT customer_id
       ,product_id
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, product_id
ORDER BY customer_id, product_id),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROm level1),
level3 as(SELECT *
       ,ROUND((sum_chek / total_revenue)::numeric,2) as share_product
FROm level2),
level4 as(SELECT customer_id
       ,COUNT(DISTINCT product_id) as count_unik_prod
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id),
level5 as(SELECT *
       ,SUM(share_product * share_product) OVER (partition by customer_id) as HHI
FROm level3
JOIN level4 USING (customer_id)),
level6 as(SELECT DISTINCT customer_id
       ,count_unik_prod
	   ,hhi
FROM level5),
level7 as(SELECT *
       ,ROUND(AVG(count_unik_prod) OVER ()::numeric,2) as global_avg_count_prod
FROM level6),
level8 as(SELECT * 
FROM level7
WHERE hhi >= 0.35 AND count_unik_prod > global_avg_count_prod),
level9 as(SELECT customer_id
       ,count(order_id) as count_order
FROM orders
GROUP BY customer_id)
SELECT *
FROM level8
JOIN level9 USING (customer_id)
WHERE count_order >= 6

-- 524. «Клієнт з хаотичним кошиком»

WITH level1 as(SELECT customer_id
       ,category_id
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROm orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
GROUP BY customer_id, category_id),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
	   ,COUNT(category_id) OVER (partition by customer_id) as count_category
FROm level1),
level3 as(SELECT *
       ,ROUND((sum_chek / total_revenue),4) as share_category
FROm level2),
level4 as(SELECT *
       ,ROUND(-SUM(share_category * LN(share_category)) OVER (partition by customer_id)::numeric,4) as entropy
FROM level3),
level5 as(SELECT DISTINCT customer_id
       ,count_category
	   ,entropy
FROm level4),
level6 as(SELECT *
       ,(SELECT percentile_cont(0.5) WITHIN GROUP (order by entropy) FROM level5) as median_entropy
	   ,ROUND(AVG(count_category) OVER ()::numeric,2) as global_avg_count_category
FROM level4),
level7 as(SELECT *
FROM level6
WHERE count_category > global_avg_count_category AND entropy < median_entropy),
level8 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROM orders
GROUP BY customer_id)
SELECT *
FROM level7
JOIN level8 USING (customer_id)
WHERE count_order >= 6

-- 525. «Клієнт з дорогою категорією»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,category_id
	   ,ROUND(SUM(p.unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id, category_id) as count_category_in_order
FROM orders
JOIN order_details USING (order_id)
JOIN products p USING (product_id)
JOIN categories USING (category_id)
GROUP BY customer_id, order_id, category_id),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id, category_id)::numeric,2) as avg_chek_category_in_order
FROm level1),
level3 as(SELECT distinct customer_id
       ,category_id
	   ,avg_chek_category_in_order
	   ,count_category_in_order
FROM level2),
level4 as(SELECT *
       ,MAX(avg_chek_category_in_order) OVER (partition by customer_id) as max_avg_category
FROM level3),
level5 as(SELECT *
       ,case when avg_chek_category_in_order = max_avg_category THEN 'anchor'
	   ELSE 'not_anchor' END as category_anchor
FROM level4),
level6 as(SELECT customer_id
       ,ROUND(AVG(avg_chek_category_in_order) FILTER (WHERE category_anchor = 'anchor')::numeric,2) as avg_chek_anchor
	   ,ROUND(AVG(avg_chek_category_in_order) FILTER (WHERE category_anchor = 'not_anchor')::numeric,2) as avg_chek_not_anchor
	   ,ROUND(AVG(count_category_in_order) FILTER (WHERE category_anchor = 'not_anchor')::numeric,2) as avg_count_anchor
FROM level5
GROUP By customer_id),
level7 as(SELECT *
FROm level6
WHERE avg_chek_anchor >= 1.5 * avg_chek_not_anchor AND avg_count_anchor >= 2),
level8 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROm orders
GROUP BY customer_id)
SELECT *
FROM level7
JOIN level8 USING (customer_id)
WHERE count_order >= 6

-- 526. “Клієнт із надмірною концентрацією прибутку”

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as order_revenue
	   ,ROUND(SUM((unit_price - (0.7 * unit_price)) * quantity * (1-discount))::numeric,2) as order_profit
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECt *
       ,ntile(5) OVER (partition by customer_id order by order_profit DESC) as ntile
	   ,ROUND(AVG(order_profit) OVER (partition by customer_id)::numeric,2) as avg_profit
	   ,SUM(order_profit) OVER (partition by customer_id) as total_profit
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,SUM(order_profit) FILTER (WHERE ntile = 1) OVER (partition by customer_id) as sum_profit_per_top
FROm level2),
level4 as(SELECT *
       ,ROUND((sum_profit_per_top / total_profit)::numeric,2) as ratio_top_profit
FROM level3)
SELECT *
FROm level4
WHERE ratio_top_profit >= 0.8 AND avg_profit > 0

-- 527. «Клієнт з ефектом розбитого піку»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_orders
FROm orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1),
level3 as(SELECT *
       ,case when sum_chek > prev_chek AND sum_chek > next_chek THEN 1 ELSE 0 END flag_high_chek 
FROM level2
WHERE prev_chek is not null and next_chek is not null),
level4 as(SELECT *
       ,SUM(flag_high_chek) OVER (partition by customer_id) as sum_flag_high_chek
FROm level3),
level5 as(SELECT DISTINCT customer_id
       ,count_orders
	   ,avg_chek
	   ,sum_flag_high_chek
	   ,ntile(4) OVER (order by avg_chek DESC) as ntile
FROm level4)
SELECT *
FROm level5
WHERE sum_flag_high_chek = 1 AND ntile IN (1,2,3) AND count_orders >= 5

-- 528. «Клієнт з ефектом фальшивої стабільності»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
	   ,COUNT(order_id) OVER (partition by customer_id) / 2 as middle_point
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
FROM orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,ROUND(STDDEV(sum_chek) OVER (partition by customer_id)::numeric,2) as std_dev_chek
	   ,case when rn <= middle_point THEN 'first'
	   when rn > middle_point THEN 'second'
	   END as halfs
FROm level1
WHERE count_order >= 6),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as avg_chek_second
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE halfs = 'first')::numeric,2) as stddev_chek_first
	   ,ROUND(STDDEV(sum_chek) FILTER (WHERE halfs = 'second')::numeric,2) as stddev_chek_second
FROm level2
GROUP By customer_id),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek_second - avg_chek_first) / avg_chek_first)::numeric,2) as diff_chek
	   ,ROUND((stddev_chek_second::numeric / stddev_chek_first::numeric),2) as diff_stddev
FROm level3)
SELECT *
FROm level4
WHERE diff_chek <= 0.05 AND diff_stddev >= 1.5