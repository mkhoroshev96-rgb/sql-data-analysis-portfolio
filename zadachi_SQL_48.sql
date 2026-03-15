-- 303. “Клієнти з підозрілим зламом кошика по категоріях”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as total_qty
	   ,COUNT(distinct category_id) as count_unik_category
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
JOIN products USING(product_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
FROM level2
WHERE rn = 1 OR rn_invert=1),
level4 as(SELECT customer_id
       ,ROUND(AVG(total_qty) FILTER (where rn = 1)::numeric,2) as avg_qty_first
	   ,ROUND(AVG(total_qty) FILTER (Where rn_invert = 1)::numeric,2) as avg_qty_last
	   ,ROUND(AVG(count_unik_category) FILTER (where rn = 1)::numeric,2) as count_unik_cat_first
	   ,ROUND(AVG(count_unik_category) FILTER (where rn_invert = 1)::numeric,2) as count_unik_cat_last
FROM level3
GROUP BY customer_id)
SELECT *
FROM level4
WHERE avg_qty_last >= avg_qty_first * 2 AND count_unik_cat_last <= count_unik_cat_first - 2

-- 304. “Клієнти з розширенням асортименту без повернення до старту”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
FROM orders
JOIN order_details USING (order_id)
ORDER BY customer_id,order_date),
level2 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id,order_id order by order_date) as rn
FROM level1),
level3 as(SELECT *
       ,DENSE_RANK () OVER (partition by customer_id order by order_date) as rank_rn
	   ,DENSE_RANK () OVER (partition by customer_id order by order_date DESC) as rank_rn_invert
FROM level2),
level4 as(SELECT *
FROM level3
WHERE rank_rn = 1 OR rank_rn_invert = 1),
level5 as(SELECT customer_id
       ,order_id
	   ,COUNT(DISTINCT product_id) as count_unik_prod
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm level1
GROUP By customer_id, order_id),
level6 as(SELECT *
FROM level4
JOIN level5 USING(customer_id, order_id)),
level7 as(SELECT *
FROM level6
WHERE count_order >= 8),
level8 as(SELECT customer_id
       ,COUNT(DISTINCT product_id) as count_unik_prod_per_customer
FROm level7
GROUP By customer_id),
level9 as(SELECT *
FROM level7
JOIN level8 USING(customer_id)),
level10 as(SELECT customer_id
       ,count_unik_prod_per_customer
       ,ROUND(AVG(count_unik_prod) FILTER (WHERE rank_rn = 1)::numeric,0) as count_unik_prod_first
	   ,ROUND(AVG(count_unik_prod) FILTER (WHERE rank_rn_invert = 1)::numeric,0) as count_unik_prod_last
FROM level9
GROUP By customer_id, count_unik_prod_per_customer)
SELECT *
FROM level10
WHERE count_unik_prod_last >= count_unik_prod_first AND count_unik_prod_per_customer <= 0.2 * count_unik_prod_first

-- 305. “Клієнти з вибухом кількості без росту чеку”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING(order_id)
GROUP By customer_id,order_id,order_date),
level2 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,case when rn <= 2 THEN 'first_orders' ELSE 'other' END as fir_ord
	   ,case when rn_invert <= 2 THEN 'last_orders' ELSE 'other' END as las_ord
FROm level2),
level4 as(SELECT customer_id
       ,ROUND(AVG(sum_quantity) FILTER (where fir_ord = 'first_orders')::numeric,2) as avg_quantity_first
	   ,ROUND(AVG(sum_quantity) FILTER (where las_ord = 'last_orders')::numeric,2) as avg_quantity_last
	   ,ROUND(AVG(sum_chek) FILTER (where fir_ord = 'first_orders')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (where las_ord = 'last_orders')::numeric,2) as avg_chek_last
FROm level3
GROUP BY customer_id)
SELECT *
FROM level4
WHERE avg_quantity_last >= 2 * avg_quantity_first AND avg_chek_last <= 1.1 * avg_chek_first

-- 306. “Клієнти з перекосом ціни: дорожче, але не більше”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id,order_date),
level2 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM level1
WHERE count_order >= 7),
level3 as(SELECT *
       ,CASE WHEN rn <= 3 THEN 'first_orders' ELSE 'other' END as flag_first
	   ,CASE WHEN rn_invert <= 3 THEN 'last_orders' ELSE 'other' END as flag_last
FROM level2),
level4 as(SELECT customer_id
       ,ROUND(AVG(avg_price) FILTER (WHERE flag_first = 'first_orders')::numeric,2) as avg_price_first
	   ,ROUND(AVG(avg_price) FILTER (WHERE flag_last = 'last_orders')::numeric,2) as avg_price_last
	   ,ROUND(AVG(sum_chek) FILTER (WHERE flag_first = 'first_orders')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (WHERE flag_last = 'last_orders')::numeric,2) as avg_chek_last
FROM level3 
GROUP By customer_id)
SELECT *
FROm level4 
WHERE avg_price_last > 1.5 * avg_price_first AND avg_chek_last <= 1.2 * avg_chek_first

-- 307. «Клієнти з ефектом прискорення»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIn order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(order_date) OVER (partition by customer_id order by order_date) as prev_date
	   ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek 
FROm level1
WHERE count_order >= 6),
level3 as(SELECT *
       ,order_date - prev_date as interval
FROM level2
WHERE prev_date is not null AND prev_chek is not null),
level4 as(SELECT *
       ,ROW_NUMBER () OVER (partition by customer_id order by order_date) as rn
	   ,ROW_NUMBER () OVER (partition by customer_id order by order_date DESC) as rn_invert
FROM level3),
level5 as(SELECT *
       ,case when rn <= 3 THEN 'first_3' ELSE 'other' END as flag_first
	   ,case when rn_invert <= 3 THEN 'last_3' ELSE 'other' END as flag_last
FROM level4),
level6 as(SELECT customer_id
       ,ROUND(AVG(interval) FILTER (WHERE flag_first = 'first_3')::numeric,2) as avg_interval_first
	   ,ROUND(AVG(interval) FILTER (WHERE flag_last = 'last_3')::numeric,2) as avg_interval_last
	   ,ROUND(AVG(prev_chek) FILTER (WHERE flag_first = 'first_3')::numeric,2) as avg_chek_first
	   ,ROUND(AVG(prev_chek) FILTER (WHERE flag_last = 'last_3')::numeric,2) as avg_chek_last
FROM level5
GROUP BY customer_id)
SELECT *
FROM level6
WHERE avg_interval_last <= 0.6 * avg_interval_first AND avg_chek_last <= 1.1 * avg_chek_first