-- 443.«Клієнт із локальною стабільністю»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
	   ,LEAD(sum_chek) OVER (partition by customer_id order by order_date) as next_chek
	   ,ROUND(AVG(sum_chek) OVER (partition by customer_id)::numeric,2) as avg_chek
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when ABS(sum_chek - prev_chek) <= ABS(prev_chek - avg_chek) 
	   AND ABS(sum_chek - next_chek) <= ABS(next_chek - avg_chek) THEN 1 ELSE 0
	   END as flags_delta
FROM level2
WHERE prev_chek is not null AND next_chek is not null),
level4 as(SELECT *
       ,SUM(flags_delta) OVER (partition by customer_id) as sum_flag_delta
FROm level3),
level5 as(SELECT *
       ,case when ABS(sum_chek - avg_chek) > ABS(prev_chek - avg_chek) 
	   AND ABS(sum_chek - avg_chek) > ABS(next_chek - avg_chek) THEN 1 ELSE 0
	   END as is_not_avg_chek
FROm level4
WHERE sum_flag_delta >= 2),
level6 as(SELECT *
       ,LAG(flags_delta) OVER (partition by customer_id) as prev_flags_delta
	   ,LEAD(flags_delta) OVER (partition by customer_id) as next_flags_delta
FROM level5),
level7 as(SELECT *
       ,case when prev_flags_delta = 0 AND flags_delta = 1 AND next_flags_delta = 0 THEN 'yes'
	   ELSE 'no' END as groups
FROM level6)
SELECT *
FROM level7
WHERE flags_delta = 1 AND is_not_avg_chek = 1 AND groups = 'yes'

-- 444. «Клієнт із зламаною ієрархією товарів»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,quantity
	   ,MAX(quantity) OVER (partition by customer_id, order_id) as max_product_quantity
	   ,SUM(quantity) OVER (partition by customer_id, order_id) as total_quantity
FROM orders
JOIN order_details USING(order_id)
ORDER BY customer_id, order_id),
level2 as(SELECT *
       ,ROUND((max_product_quantity::numeric / total_quantity::numeric),2) as dominance_ratio
FROm level1),
level3 as(SELECT DISTINCT customer_id, order_id
       ,max_product_quantity
	   ,total_quantity
	   ,dominance_ratio
FROM level2
ORDER BY customer_id, order_id),
level4 as(SELECT *
       ,ROUND(AVG(total_quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
	   ,ROUND(AVG(dominance_ratio) OVER (partition by customer_id)::numeric,2) as avg_dominance_ratio
	   ,MAX(total_quantity) OVER (partition by customer_id) as max_quantity
	   ,MIN(dominance_ratio) OVER (partition by customer_id) as min_dominance_ratio
FROM level3),
level5 as(SELECT *
FROM level4
WHERE dominance_ratio < avg_dominance_ratio AND total_quantity > avg_quantity 
AND total_quantity <> max_quantity AND dominance_ratio <> min_dominance_ratio),
level6 as(SELECT *
       ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM level5),
level7 as(SELECT *
FROM level6
WHERE count_order = 1),
level8 as(SELECT customer_id
       ,COUNT(order_id) as count_order_per_customer
FROM orders
GROUP BY customer_id)
SELECT *
FROm level7
JOIN level8 USING (customer_id)
WHERE count_order_per_customer >= 5

-- 445. «Клієнт із порушеною пропорцією»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as revenue
	   ,ROUND(AVG(freight)::numeric,2) as avg_freight
	   ,count(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROUND((avg_freight / revenue),4) as shipping_ratio
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,ROUND(AVG(shipping_ratio) OVER (partition by customer_id)::numeric,4) as avg_shipping_ratio
	   ,ROUND(AVG(avg_freight) OVER (partition by customer_id)::numeric,2) as avg_freight_per_customer
	   ,MIN(shipping_ratio) OVER (partition by customer_id) as min_shipping_ratio
	   ,MAX(avg_freight) OVER (partition by customer_id) as max_avg_freight
FROM level2),
level4 as(SELECT *
FROM level3
WHERE shipping_ratio < avg_shipping_ratio AND avg_freight > avg_freight_per_customer
AND shipping_ratio <> min_shipping_ratio AND avg_freight <> max_avg_freight),
level5 as(SELECT *
       ,COUNT(order_id) OVER (partition by customer_id) as count_yes
FROM level4)
SELECT *
FROM level5
WHERE count_yes = 1

-- 446. «Клієнт, який купує “по алфавіту”»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,product_name
	   ,FIRST_VALUE(product_name) OVER (partition by customer_id,order_id order by product_name) as first_name
	   ,FIRST_VALUE(product_name) OVER (partition by customer_id, order_id ORDER BY product_name DESC) as last_name
FROM orders
JOIN order_details USING (order_id)
JOIN products USING (product_id)),
level2 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROM orders
GROUP By customer_id),
level3 as(SELECT *
FROM level1
JOIN level2 USING (customer_id)
WHERE count_order >= 6),
level4 as(SELECT DISTINCT customer_id, order_id,first_name, last_name,count_order
FROm level3
ORDER BY customer_id, order_id),
level5 as(SELECT *
       ,LAG(last_name) OVER (partition by customer_id order by order_id) as prev_last_name
FROm level4),
level6 as(SELECT *
       ,case when first_name > prev_last_name THEN 1 ELSE 0 END as flag_name
FROm level5),
level7 as(SELECT *
       ,SUM(flag_name) OVER (partition by customer_id) as sum_flag_name
	   ,LAG(flag_name) OVER (partition by customer_id order by order_id) as prev_flag_name
	   ,LEAD(flag_name) OVER (partition by customer_id order by order_id) as next_flag_name
FROM level6),
level8 as(SELECT *
       ,case when prev_flag_name = 0 AND flag_name = 1 AND next_flag_name = 0 THEN 'yes'
	   ELSE 'no' END as groups
FROM level7
WHERE sum_flag_name >= 3),
level9 as(SELECT *
       ,COUNT(*) FILTER (WHERE groups = 'yes') OVER (partition by customer_id) as count_yes
FROM level8
WHERE groups = 'yes')
SELECT *
FROM level9
WHERE count_yes >= 3

-- 447. «Замовлення з ілюзією повтору»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
FROM level1)
SELECT *
FROm level2
WHERE sum_quantity = prev_quantity

