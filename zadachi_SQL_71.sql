-- 448. «Замовлення з прихованим повтором»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,quantity
	   ,MAX(quantity) OVER (partition by customer_id, order_id) as max_quantity_order
	   ,SUM(quantity) OVER (partition by customer_id, order_id) as sum_quantity_order
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,count(order_id) OVER (partition by customer_id, order_id) as count_order
	   ,ROUND((max_quantity_order::numeric / sum_quantity_order::numeric),2) as ratio
FROm level1
WHERE quantity = max_quantity_order),
level3 as(SELECT *
       ,LAG(ratio) OVER (partition by customer_id order by order_date) as prev_ratio
	   ,LAG(product_id) OVER (partition by customer_id order by order_date) as prev_product_id
FROM level2
WHERE count_order = 1)
SELECT *
FROM level3
WHERE ratio = prev_ratio AND product_id <> prev_product_id

-- 449. «Замовлення з нульовим ефектом»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
FROM orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,order_id
	   ,COUNT(DISTINCT product_id) as count_unik_prod
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id),
level3 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
	   ,LAG(count_unik_prod) OVER (partition by customer_id order by order_date) as prev_count_unik_prod
FROM level1
JOIN level2 USING (customer_id, order_id))
SELECT *
FROm level3
WHERE count_unik_prod <> prev_count_unik_prod AND sum_quantity = prev_quantity 

-- 450. «Замовлення з перевернутою ціною»

WITh level1 as(select customer_id
       ,order_id
	   ,order_date
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROM orders
JOIN order_details USING (order_id)
GROUP By customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(avg_price) OVER (partition by customer_id order by order_date) as prev_price
	   ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1)
SELECT *
FROM level2
WHERE avg_price > prev_price AND sum_chek < prev_chek

-- 451. «Замовлення з порушеним балансом»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
	   ,ROUND(AVG(unit_price)::numeric,2) as avg_price
	   ,ROUND(SUM(unit_price * quantity * (1-discount))::numeric,2) as sum_chek
FROm orders
JOIn order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
	   ,LAG(avg_price) OVER (partition by customer_id order by order_date) as prev_price
	   ,LAG(sum_chek) OVER (partition by customer_id order by order_date) as prev_chek
FROM level1),
level3 as(SELECT *
       ,ROUND((ABS((sum_chek - prev_chek) / prev_chek)*100)::numeric,2) as diff_chek
FROm level2)
SELECT *
FROM level3
WHERE diff_chek <= 1 AND sum_quantity > prev_quantity AND avg_price < prev_price

-- 452. «Замовлення з зруйнованою домінантою»

WITh level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id
	   ,quantity
	   ,MAX(quantity) OVER (partition by customer_id, order_id) as max_quantity
FROM orders
JOIN order_details USING (order_id)),
level2 as(SELECT *
       ,ROW_number () OVER (partition by customer_id,order_id order by quantity DESC) as rn
FROM level1),
level3 as(SELECT *
       ,LAG(product_id) OVER (partition by customer_id order by order_date) as prev_product
FROM level2
WHERE rn = 1),
level4 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,product_id as prod
	   ,quantity as qnt
FROM orders
JOIN order_details USING (order_id)),
level5 as(SELECT *
FROM level3
JOIN level4 USING (customer_id, order_id,order_date)
ORDER BY customer_id, order_id, order_date),
level6 as(SELECT *
       ,ROW_number () OVER (partition by customer_id, order_id order by qnt DESC) as rn_qnt
FROM level5)
SELECT *
FROM level6
WHERE prev_product is not null 
AND prev_product = prod
AND rn <> rn_qnt

-- 453. «Замовлення з зламаним масштабом»

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,SUM(quantity) as sum_quantity
FROm orders
JOIN order_details USING(order_id)
GROUP BY customer_id, order_id, order_date),
level2 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,COUNT(DISTINCT product_id) as count_unik_prod
FROM orders
JOIN order_details USING (order_id)
GROUP BY customer_id, order_id, order_date),
level3 as(SELECT *
       ,ROUND((sum_quantity::numeric / count_unik_prod::numeric),2) as ratio
FROM level1
JOIN level2 USING (customer_id, order_id, order_date)),
level4 as(SELECT *
       ,LAG(sum_quantity) OVER (partition by customer_id order by order_date) as prev_quantity
	   ,LAG(ratio) OVER (partition by customer_id order by order_date) as prev_ratio
FROM level3)
SELECT *
FROM level4
WHERE prev_quantity is not null AND prev_ratio is not null
AND sum_quantity > prev_quantity AND ratio < prev_ratio

-- 454. Замовлення - дублікати

WITH level1 as(SELECT customer_id
       ,order_id
	   ,order_date
	   ,COUNT(order_date) as count_dublikate
FROM orders
GROUP By customer_id, order_id, order_date)
SELECT *
FROM level1
WHERE count_dublikate > 1