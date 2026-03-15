-- 334. “Клієнти з анти-ефектом масштабу”

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROm orders
JOIN order_details USING(order_id)
GROUP By customer_id,order_id, order_date),
level2 as(SELECT *
       ,ROW_NUMBER() OVER (partition by customer_id order by order_date) as rn_first
	   ,ROW_NUMBER() OVER (partition by customer_id order by order_date DESC) as rn_last
FROm level1
WHERE count_order >= 5),
level3 as(SELECT customer_id
       ,ROUND(AVG(sum_chek) FILTER (WHere rn_first <= 2)::numeric,2)  as avg_chek_first
	   ,ROUND(AVG(sum_chek) FILTER (where rn_last <= 2)::numeric,2) as avg_chek_last
FROM level2
GROUP By customer_id)
SELECT *
FROM level3
WHERE avg_chek_first > avg_chek_last

-- 335. “Клієнти з ілюзією активності”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
	   ,COUNT(order_id) OVER (partition by customer_id) as count_order
FROM orders
JOIN order_details USING(order_id)
GROUP by customer_id, order_id, order_date),
level2 as(SELECT *
       ,SUM(sum_chek) OVER (partition by customer_id) as total_revenue
FROm level1
WHERE count_order >= 5),
level3 as(SELECT DISTINCT customer_id
       ,count_order
	   ,total_revenue
FROM level2),
level4 as(SELECT *
       ,DENSE_RANK () OVER (order by count_order DESC) as rn_count_order
	   ,NTILE(4) OVER (order by count_order DESC) as ntile_count_order
FROM level3),
level5 as(SELECT customer_id
       ,DENSE_RANK () OVER (order by total_revenue) as rn_revenue
	   ,NTILE(4) OVER (order by total_revenue) as ntile_revenue
FROM level4)
SELECT *
FROM level4
JOIN level5 USING(customer_id)
WHERE ntile_count_order = 1 AND ntile_revenue = 1

-- 336. “Замовлення з ефектом маскування”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,unit_price
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT *
       ,ROUND(AVG(unit_price) OVER (partition by customer_id, order_id)::numeric,2) as avg_price
	   ,ROUND(AVG(unit_price) OVER ()::numeric,2) as global_avg_price
FROm level1),
level3 as(SELECT customer_id
       ,order_id
	   ,COUNT(DISTINCT product_id) as count_unikal_product
FROM level2
GROUP BY customer_id, order_id),
level4 as(SELECT *
FROM level2
JOIN level3 USING (customer_id, order_id)),
level5 as(SELECT *
       ,ROUND(ABS((avg_price - global_avg_price) / global_avg_price)::numeric,2) as diff_price
	   ,ROUND((unit_price / global_avg_price)::numeric,2) as ratio_price
FROM level4
WHERE count_unikal_product >= 3),
level6 as(SELECT *
       ,MAX(ratio_price) OVER (partition by customer_id, order_id) as max_ratio
	   ,MIN(ratio_price) OVER (partition by customer_id, order_id) as min_ratio
FROM level5
WHERE diff_price <= 0.1)
SELECT *
FROM level6
WHERE max_ratio >= 1.5 AND min_ratio <= 0.5

-- 337. “Замовлення з ефектом компенсації”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,unit_price
	   ,quantity
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as chek
FROm orders
JOIN order_details USING(order_id)),
level2 as(SELECT customer_id
       ,order_id
       ,COUNT(DISTINCT product_id) as count_unik_product
FROM level1
GROUP BY customer_id, order_id),
level3 as(SELECT *
       ,ROUND(AVG(unit_price) OVER (partition by customer_id, order_id)::numeric,2) as avg_price
	   ,ROUND(AVG(unit_price) OVER ()::numeric,2) as global_avg_price
	   ,ROUND(AVG(quantity) OVER (partition by customer_id, order_id)::numeric,2) as avg_quantity
	   ,ROUND(AVG(quantity) OVER ()::numeric,2) as global_avg_quantity
	   ,ROUND(AVG(chek) OVER (partition by customer_id, order_id)::numeric,2) as avg_chek
	   ,ROUND(AVG(chek) OVER ()::numeric,2) as global_avg_chek
FROM level1
JOIN level2 USING(customer_id, order_id)
WHERE count_unik_product >= 3),
level4 as(SELECT *
       ,ROUND(ABS((avg_chek - global_avg_chek) / global_avg_chek)::numeric,2) as diff_chek
FROm level3
WHERE avg_price >= global_avg_price AND avg_quantity <= global_avg_quantity)
SELECT *
FROM level4
WHERE diff_chek <= 0.1

-- 338. “Клієнти з ефектом псевдо-різноманіття”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,product_id
	   ,unit_price
	   ,quantity
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT customer_id
       ,COUNT(DISTINCT product_id) as count_unik_product
FROM level1
GROUP By customer_id),
level3 as(SELECT *
       ,ROUND(STDDEV(unit_price) OVER (partition by customer_id)::numeric,2) as stddev_price
	   ,ROUND(AVG(unit_price) OVER (partition by customer_id)::numeric,2) as avg_price
	   ,ROUND(STDDEV(quantity) OVER (partition by customer_id)::numeric,2) as stddev_quantity
	   ,ROUND(AVG(quantity) OVER (partition by customer_id)::numeric,2) as avg_quantity
FROM level1
JOIN level2 USING (customer_id)
WHERE count_unik_product >= 8
ORDER BY customer_id),
level4 as(SELECT DISTINCT customer_id
       ,ROUND((stddev_price / avg_price)::numeric,2) as diff_price
	   ,ROUND((stddev_quantity / avg_quantity)::numeric,2) as diff_quantity
FROm level3)
SELECT *
FROM level4
WHERE diff_price <= 0.1 AND diff_quantity >= 0.5

-- 339. “Клієнти з перевернутою цінністю”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as chek
FROm orders
JOIN order_details USING(order_id)),
level2 as(SELECT customer_id
       ,COUNT(order_id) as count_order
FROM level1
GROUP BY customer_id),
level3 as(SELECT *
       ,ROUND(AVG(chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	   ,SUM(chek) OVER (partition by customer_id) as sum_chek
FROM level1
JOIN level2 USING(customer_id)),
level4 as(SELECT DISTINCT customer_id
       ,count_order
	   ,avg_chek
	   ,sum_chek
FROM level3),
level5 as(SELECT customer_id
       ,DENSE_RANK() OVER (order by count_order DESC) as rank_count
	   ,NTILE(5) OVER (order by count_order DESC) as ntile_count
FROM level4),
level6 as(SELECT customer_id
       ,DENSE_RANK () OVER (order by avg_chek DESC) as rank_avg_chek
	   ,NTILE(5) OVER (order by avg_chek DESC) as ntile_avg_chek
FROM level4),
level7 as(SELECT customer_id
       ,DENSE_RANK () OVER (order by sum_chek DESC) as rank_sum_chek
	   ,NTILE(5) OVER (order by sum_chek DESC) as ntile_sum_chek
FROM level4),
level8 as(SELECT *
FROM level4
JOIn level5 USING(customer_id)
JOIN level6 USING(customer_id)
JOIN level7 USING(customer_id)
WHERE ntile_count = 3 AND ntile_avg_chek = 1)
SELECT *
FROm level8
WHERE ntile_sum_chek IN (2,3,4,5)

-- 340. “Клієнти з ефектом прихованого ризику”

WITH level1 as(SELECT customer_id
       ,order_id
	   ,ROUND((unit_price * quantity * (1-discount))::numeric,2) as chek
FROM orders
JOIN order_details USING(order_id)),
level2 as(SELECT customer_id
	   ,COUNT(DISTINCT order_id)  as count_order
FROM level1
GROUP By customer_id),
level3 as(SELECT *
          ,ROUND(AVG(chek) OVER (partition by customer_id)::numeric,2) as avg_chek
	      ,SUM(chek) OVER (partition by customer_id) as sum_chek
FROM level1
JOIN level2 USING(customer_id)),
level4 as(SELECT DISTINCT customer_id
       ,count_order
	   ,avg_chek
	   ,sum_chek
FROM level3),
level5 as(SELECT customer_id
       ,DENSE_RANK() OVER (order by count_order DESC) as rank_count
	   ,NTILE(5) OVER (order by count_order DESC) as ntile_count
FROM level4),
level6 as(SELECT customer_id
       ,DENSE_RANK () OVER (order by avg_chek DESC) as rank_avg_chek
	   ,NTILE(5) OVER (order by avg_chek DESC) as ntile_avg_chek
FROm level4),
level7 as(SELECT customer_id
       ,DENSE_RANK() OVER (order by sum_chek DESC) as rank_sum_chek
	   ,NTILE(5) OVER (order by sum_chek DESC) as ntile_sum_chek
FROM level4)
SELECT *
FROM level4
JOIN level5 USING(customer_id)
JOIN level6 USING(customer_id)
JOIN level7 USING(customer_id)
WHERE ntile_count = 2 AND ntile_avg_chek = 2 AND ntile_sum_chek = 2

